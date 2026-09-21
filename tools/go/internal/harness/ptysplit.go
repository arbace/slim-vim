package harness

import (
	"os"
	"os/exec"
	"sync"
	"syscall"
	"time"
)

// PtySplit is zero30's `zsig.py` run(): the editor on a real pty with FD 2 ON
// A PIPE OF ITS OWN, keys typed on a clock, then one signal.
//
// THE SEPARATE fd 2 IS THE WHOLE POINT.  exit_scroll()'s printf arm writes
// `\r\n` to STDERR and its other arm writes the same two bytes to STDOUT, so on
// a pty where both are the same device the combined stream is byte-identical
// either way.  Split the descriptors and it is two bytes moving from one to
// the other.
//
// The timing is the Python's, step for step, because the rows it feeds carry
// byte counts: 0.3 s before each key and 0.35 s of reading after it, `delay`
// before the signal, then 2.0 s of reading.  What arrives AFTER that last
// window is not collected, as it was not collected there -- the readers keep
// draining so the child cannot block, but the result is taken at the end of
// the window.  sig 0 sends none.
//
// It is in the harness and not in the check because the pty primitives are
// unexported here, and in a file of its own because two sessions edit this
// package's existing files.
func PtySplit(binary string, args []string, keys [][]byte, sig syscall.Signal,
	delay time.Duration, term string, rows, cols int) ([]byte, []byte, int, error) {

	vim, err := Stage(binary)
	if err != nil {
		return nil, nil, -1, err
	}
	home, err := os.MkdirTemp("", "zsig-")
	if err != nil {
		return nil, nil, -1, err
	}
	defer os.RemoveAll(home)

	m, slaveName, err := openPty()
	if err != nil {
		return nil, nil, -1, err
	}
	defer m.Close()
	slave, err := os.OpenFile(slaveName, os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		return nil, nil, -1, err
	}
	ws := winsize{rows: uint16(rows), cols: uint16(cols)}
	ioctl(slave, syscall.TIOCSWINSZ, unsafePointerOf(&ws))
	er, ew, err := os.Pipe()
	if err != nil {
		slave.Close()
		return nil, nil, -1, err
	}

	cmd := exec.Command(vim, args...)
	cmd.Env = append(Env(home), "TERM="+term)
	cmd.Dir = home
	cmd.Stdin, cmd.Stdout, cmd.Stderr = slave, slave, ew
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true, Setctty: true}
	if err := cmd.Start(); err != nil {
		slave.Close()
		er.Close()
		ew.Close()
		return nil, nil, -1, err
	}
	slave.Close()
	ew.Close()

	var mu sync.Mutex
	var out, errb []byte
	var wg sync.WaitGroup
	drain := func(f *os.File, into *[]byte) {
		defer wg.Done()
		buf := make([]byte, 65536)
		for {
			n, e := f.Read(buf)
			if n > 0 {
				mu.Lock()
				*into = append(*into, buf[:n]...)
				mu.Unlock()
			}
			if e != nil {
				return
			}
		}
	}
	wg.Add(2)
	go drain(m, &out)
	go drain(er, &errb)

	for _, k := range keys {
		time.Sleep(300 * time.Millisecond)
		m.Write(k)
		time.Sleep(350 * time.Millisecond)
	}
	if sig != 0 {
		time.Sleep(delay)
		if cmd.Process != nil {
			cmd.Process.Signal(sig)
		}
	}
	time.Sleep(2 * time.Second)
	mu.Lock()
	gotOut := append([]byte(nil), out...)
	gotErr := append([]byte(nil), errb...)
	mu.Unlock()

	st := -1
	cmd.Wait()
	if cmd.ProcessState != nil {
		if w, ok := cmd.ProcessState.Sys().(syscall.WaitStatus); ok {
			st = waitStatusInt(w)
		}
	}
	m.Close()
	er.Close()
	wg.Wait()
	return gotOut, gotErr, st, nil
}
