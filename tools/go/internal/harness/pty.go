package harness

import (
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"syscall"
	"time"
	"unsafe"
)

// ansi is what a screen capture strips: CSI sequences, charset selects, the
// two single-character ones, OSC strings, and the carriage returns a terminal
// uses for cursor motion rather than for text.
var ansi = regexp.MustCompile(`\x1b\[[0-9;?]*[a-zA-Z]|\x1b[()][0-9A-B]|\x1b[=>]|\x1b\][^\x07]*\x07|\r`)

// ioctl runs one ioctl on a file WITHOUT disturbing Go's poller.
//
// os.File.Fd() is the obvious way and the wrong one: it puts the file into
// BLOCKING mode and takes it out of the runtime's poller, after which
// SetReadDeadline does nothing at all and a Read on a pty master the child
// keeps open never returns.  Measured the hard way -- the first version of
// this file hung every session instead of timing out.  SyscallConn.Control
// hands over the descriptor without changing its mode.
func ioctl(f *os.File, req uintptr, arg unsafe.Pointer) error {
	c, err := f.SyscallConn()
	if err != nil {
		return err
	}
	var errno syscall.Errno
	if err := c.Control(func(fd uintptr) {
		_, _, errno = syscall.Syscall(syscall.SYS_IOCTL, fd, req, uintptr(arg))
	}); err != nil {
		return err
	}
	if errno != 0 {
		return errno
	}
	return nil
}

// openPty opens a pseudo-terminal pair on Linux, with no third-party
// dependency: /dev/ptmx, unlock, ask for the number, open the slave.
func openPty() (master *os.File, slaveName string, err error) {
	m, err := os.OpenFile("/dev/ptmx", os.O_RDWR, 0)
	if err != nil {
		return nil, "", err
	}
	var unlock int32
	if err := ioctl(m, syscall.TIOCSPTLCK, unsafe.Pointer(&unlock)); err != nil {
		m.Close()
		return nil, "", err
	}
	var n uint32
	if err := ioctl(m, syscall.TIOCGPTN, unsafe.Pointer(&n)); err != nil {
		m.Close()
		return nil, "", err
	}
	return m, fmt.Sprintf("/dev/pts/%d", n), nil
}

// winsize is what TIOCSWINSZ takes.
type winsize struct {
	rows, cols, x, y uint16
}

// unsafePointerOf lets another file in this package hand a winsize to ioctl
// without importing unsafe itself.
func unsafePointerOf(v *winsize) unsafe.Pointer { return unsafe.Pointer(v) }

// Session runs the binary under a pty, types the keys, and returns the output
// with ANSI sequences stripped, plus the wait status.
//
// Each key string is written and then followed by settle seconds of reading.
// A hard deadline is on the read loop on purpose: an error at startup leaves
// vim on a Press ENTER prompt, and without one the loop would hang for ever.
//
// The window size is set on the SLAVE before the child execs.  Setting it on
// the master after a fork is a bet that the parent beats the child's startup,
// and losing it leaves a 24-row scroll region on a 30-row screen, where three
// message lines overwrite each other on the bottom row -- measured at 16 of 60
// runs failing before the fix and 0 of 60 after.
func Session(binary string, args []string, keys [][]byte, term string,
	timeout, settle time.Duration, cwd string, env []string, rows, cols int) ([]byte, int, error) {

	vim, err := Stage(binary)
	if err != nil {
		return nil, -1, err
	}

	m, slaveName, err := openPty()
	if err != nil {
		return nil, -1, err
	}
	defer m.Close()

	slave, err := os.OpenFile(slaveName, os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		return nil, -1, err
	}
	defer slave.Close()

	if rows > 0 && cols > 0 {
		ws := winsize{rows: uint16(rows), cols: uint16(cols)}
		ioctl(slave, syscall.TIOCSWINSZ, unsafe.Pointer(&ws))
	}

	e := env
	if e == nil {
		e = os.Environ()
	}
	e = withTerm(e, term)

	cmd := exec.Command(vim, args...)
	cmd.Env = e
	cmd.Dir = cwd
	cmd.Stdin, cmd.Stdout, cmd.Stderr = slave, slave, slave
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true, Setctty: true}
	if err := cmd.Start(); err != nil {
		return nil, -1, err
	}
	slave.Close()

	var out []byte
	deadline := time.Now().Add(timeout)
	buf := make([]byte, 65536)

	// A read deadline that cannot be set is the difference between a session
	// that times out and one that hangs for ever, so it is checked once and
	// loudly rather than ignored per read.
	if err := m.SetReadDeadline(time.Now().Add(time.Second)); err != nil {
		return nil, -1, fmt.Errorf("pty: the master takes no read deadline (%v) -- "+
			"a session would hang rather than time out", err)
	}

	drain := func(until time.Time) {
		for time.Now().Before(until) {
			m.SetReadDeadline(time.Now().Add(50 * time.Millisecond))
			n, err := m.Read(buf)
			if n > 0 {
				out = append(out, buf[:n]...)
			}
			if err != nil {
				if os.IsTimeout(err) {
					continue
				}
				return
			}
		}
	}

	drain(minTime(time.Now().Add(settle*2), deadline))
	for _, k := range keys {
		if time.Now().After(deadline) {
			break
		}
		if _, err := m.Write(k); err != nil {
			break
		}
		drain(minTime(time.Now().Add(settle), deadline))
	}

	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	status := -1
	select {
	case werr := <-done:
		status = 0
		if ee, ok := werr.(*exec.ExitError); ok {
			status = ee.ExitCode()
		}
	case <-time.After(time.Until(deadline)):
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
		<-done
	}
	return ansi.ReplaceAll(out, nil), status, nil
}

func withTerm(env []string, term string) []string {
	var out []string
	for _, kv := range env {
		k := kv
		if i := indexByte(kv, '='); i >= 0 {
			k = kv[:i]
		}
		if k == "TERM" || k == "LINES" || k == "COLUMNS" {
			continue
		}
		out = append(out, kv)
	}
	return append(out, "TERM="+term)
}

func minTime(a, b time.Time) time.Time {
	if a.Before(b) {
		return a
	}
	return b
}

// OpenPty is openPty for a caller outside this package that drives a terminal
// of its own -- a check whose probes signal, stop and resize the child and so
// cannot be one Session.
func OpenPty() (*os.File, string, error) { return openPty() }

// SetWinsize is TIOCSWINSZ on f.  On a MASTER it resizes the terminal and the
// kernel sends the foreground process group SIGWINCH, which is how a probe
// resizes a running editor.
func SetWinsize(f *os.File, rows, cols int) error {
	ws := winsize{rows: uint16(rows), cols: uint16(cols)}
	return ioctl(f, syscall.TIOCSWINSZ, unsafe.Pointer(&ws))
}

// Termios is TCGETS on f.  On a pty master Linux answers with the slave's
// settings, which is what Python's termios.tcgetattr(master) reads too.
func Termios(f *os.File) (syscall.Termios, error) {
	var t syscall.Termios
	err := ioctl(f, syscall.TCGETS, unsafe.Pointer(&t))
	return t, err
}
