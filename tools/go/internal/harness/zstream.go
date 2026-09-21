package harness

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

// ErrBlocked is zstream.Blocked: the editor took the input over and did not
// return.
//
// `vim -` reads the keystroke FILE as buffer text, then closes fd 0 and dups
// stderr, and waits there for keys that never come.  An invocation that blocks
// is a RECORDING, not a crash, so the timeout is part of the instrument.
var ErrBlocked = errors.New("zstream: the editor took the input over and did not return")

// ZSession drives the editor with a keystroke FILE on stdin and keeps what it
// drew.
//
// Keystrokes in, screen out, and NO PTY: stdin is a file of keys, stdout a
// file of escape sequences, and the Screen turns the second into a screen.
// There is nothing to settle, no ANSI to strip, no Press-ENTER hazard and no
// timing -- the editor reads every key as fast as it can and exits, and the
// bytes it wrote are the whole recording.
//
// The terminal is 80x24 BY CONSTRUCTION: the window-size ioctl fails on a
// pipe so the editor's built-in fallback applies, and $LINES and $COLUMNS have
// decided nothing since whim's phase 19.
func ZSession(binary string, keys [][]byte, term string, args []string,
	rows, cols int, timeout time.Duration) (*Screen, []byte, []byte, int, error) {

	vim, err := Stage(binary)
	if err != nil {
		return nil, nil, nil, -1, err
	}
	home, err := os.MkdirTemp("", "zstream-home-")
	if err != nil {
		return nil, nil, nil, -1, err
	}
	defer os.RemoveAll(home)
	d, err := os.MkdirTemp("", "zstream-run-")
	if err != nil {
		return nil, nil, nil, -1, err
	}
	defer os.RemoveAll(d)

	env := append(Env(home), "TERM="+term)
	kf := filepath.Join(d, "keys")
	var all []byte
	for _, k := range keys {
		all = append(all, k...)
	}
	if err := os.WriteFile(kf, all, 0o644); err != nil {
		return nil, nil, nil, -1, err
	}
	stdin, err := os.Open(kf)
	if err != nil {
		return nil, nil, nil, -1, err
	}
	defer stdin.Close()

	cmd := exec.Command(vim, args...)
	cmd.Env = env
	cmd.Dir = d
	cmd.Stdin = stdin
	var stdout, stderr []byte
	outPipe, errPipe := &bufWriter{}, &bufWriter{}
	cmd.Stdout, cmd.Stderr = outPipe, errPipe
	// A SESSION OF ITS OWN.  :stop and :suspend signal the process GROUP with
	// SIGTSTP; without this the command sweep stopped the shell that ran it --
	// exit 148, which reads like the harness dying at command 100.
	setsid(cmd)

	if err := cmd.Start(); err != nil {
		return nil, nil, nil, -1, err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	code := 0
	select {
	case werr := <-done:
		if ee, ok := werr.(*exec.ExitError); ok {
			code = PyReturnCode(ee)
		} else if werr != nil {
			code = -1
		}
	case <-time.After(timeout):
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
		<-done
		return nil, nil, nil, -1, ErrBlocked
	}
	stdout, stderr = outPipe.b, errPipe.b

	s := NewScreen(rows, cols)
	s.Feed(stdout)
	return s, stdout, stderr, code, nil
}

// bufWriter collects a child's output.  bytes.Buffer would do; this is a
// named type only so the two streams read clearly at the call site.
type bufWriter struct{ b []byte }

func (w *bufWriter) Write(p []byte) (int, error) {
	w.b = append(w.b, p...)
	return len(p), nil
}
