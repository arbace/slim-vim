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

// openPty opens a pseudo-terminal pair on Linux, with no third-party
// dependency: /dev/ptmx, unlock, ask for the number, open the slave.
func openPty() (master *os.File, slaveName string, err error) {
	m, err := os.OpenFile("/dev/ptmx", os.O_RDWR, 0)
	if err != nil {
		return nil, "", err
	}
	var unlock int32
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, m.Fd(),
		syscall.TIOCSPTLCK, uintptr(unsafe.Pointer(&unlock))); e != 0 {
		m.Close()
		return nil, "", e
	}
	var n uint32
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, m.Fd(),
		syscall.TIOCGPTN, uintptr(unsafe.Pointer(&n))); e != 0 {
		m.Close()
		return nil, "", e
	}
	return m, fmt.Sprintf("/dev/pts/%d", n), nil
}

// winsize is what TIOCSWINSZ takes.
type winsize struct {
	rows, cols, x, y uint16
}

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
		syscall.Syscall(syscall.SYS_IOCTL, slave.Fd(),
			syscall.TIOCSWINSZ, uintptr(unsafe.Pointer(&ws)))
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
