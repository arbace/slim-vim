package harness

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

// The pty probes whim's phase checks run: one question each, asked of a real
// terminal because silent Ex mode answers a different one.
//
// THESE KEEP THE PYTHON'S FIXED SLEEPS AND THAT IS DELIBERATE.  tools/zpty.py
// was taught to wait on content -- one more \x1b[?25h, where a redraw ends --
// because a clock is a reading of the machine's load, and under enough of one
// the key goes in early: 16 of 60 runs failed before that change and 0 of 60
// after.  These probes still use a clock.  Changing that here would make the Go
// a different tool from the Python it is compared against, and that comparison
// is the only evidence the port has.  Improve both or neither; the hazard is
// recorded rather than half-fixed.

// ptyEditFile writes content to f.txt, runs the binary on it under a real pty,
// types the keys, and returns the file afterwards with newlines as spaces.
//
// The binary is staged as `vim`, because a binary's own name changes what it
// does: a basename starting with `r` is restricted mode and every shell-out
// fails, `e` selects evim, and `view`/`ex` prefixes change the mode again.
func ptyEditFile(binary, content string, keys []string, initial, perKey time.Duration) (string, error) {
	abs, err := filepath.Abs(binary)
	if err != nil {
		return "", err
	}
	d, err := os.MkdirTemp("", "ptyprobe")
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(d)

	data, err := os.ReadFile(abs)
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(filepath.Join(d, "vim"), data, 0755); err != nil {
		return "", err
	}
	if err := os.WriteFile(filepath.Join(d, "f.txt"), []byte(content), 0644); err != nil {
		return "", err
	}

	m, slaveName, err := openPty()
	if err != nil {
		return "", err
	}
	defer m.Close()
	slave, err := os.OpenFile(slaveName, os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		return "", err
	}

	cmd := exec.Command("./vim", "f.txt")
	cmd.Dir = d
	cmd.Env = probeEnv(d)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = slave, slave, slave
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true, Setctty: true}
	if err := cmd.Start(); err != nil {
		slave.Close()
		return "", err
	}
	slave.Close()

	// The Python never reads the master.  Draining costs nothing, changes
	// nothing observable, and removes the one way this could deadlock if the
	// editor ever drew more than a pty buffer holds.
	stop := make(chan struct{})
	go func() {
		buf := make([]byte, 4096)
		for {
			select {
			case <-stop:
				return
			default:
			}
			m.SetReadDeadline(time.Now().Add(200 * time.Millisecond))
			if _, err := m.Read(buf); err != nil && !os.IsTimeout(err) {
				return
			}
		}
	}()

	time.Sleep(initial)
	for _, k := range keys {
		m.Write([]byte(k))
		time.Sleep(perKey)
	}
	time.Sleep(initial)
	if cmd.Process != nil {
		cmd.Process.Kill()
	}
	cmd.Wait()
	close(stop)

	got, err := os.ReadFile(filepath.Join(d, "f.txt"))
	if err != nil {
		return "", err
	}
	return strings.ReplaceAll(string(got), "\n", " "), nil
}

// probeEnv is the isolation every harness here uses: an empty $HOME, $VIM and
// $VIMRUNTIME rather than -u NONE, because whim-vim has had no -u since its
// phase 18 and needs no option to be told.
func probeEnv(d string) []string {
	drop := map[string]bool{
		"TERM": true, "HOME": true, "VIM": true, "VIMRUNTIME": true,
		"XDG_CONFIG_HOME": true, "VIMINIT": true, "EXINIT": true, "MYVIMRC": true,
	}
	var env []string
	for _, kv := range os.Environ() {
		k := kv
		if i := strings.IndexByte(kv, '='); i >= 0 {
			k = kv[:i]
		}
		if !drop[k] {
			env = append(env, kv)
		}
	}
	return append(env,
		"TERM=xterm",
		"HOME="+d,
		"VIM="+filepath.Join(d, "novim"),
		"VIMRUNTIME="+filepath.Join(d, "novim"),
		"XDG_CONFIG_HOME="+filepath.Join(d, "xdg"))
}

// StarCheck is tools/starcheck.py: does `*` still find the next whole word?
//
// Whim phase 30 keeps `*` and `#` while removing the rest of nv_ident(), and no
// behaviour case presses `*`.
//
// IT HAS TO BE A PTY.  The first version of this check ran the editor under
// -e -s and compared the file afterwards, and the two binaries disagreed: before
// the phase `:normal *dd` did nothing at all, after it the `*` was ignored and
// the `dd` deleted line 1.  Neither is what `*` does -- normal_search() wants a
// screen, so silent Ex mode measures something that is not the feature.
//
// The buffer is foo/bar/foobar/baz/foo with the cursor on line 1.  `*` must NOT
// stop on `foobar`, which is not a whole word, and must stop on line 5; `dd`
// then deletes whatever it landed on, so the file that comes back says where it
// went.
func StarCheck(binary string, out *os.File) error {
	const want = "foo bar foobar baz "
	got, err := ptyEditFile(binary, "foo\nbar\nfoobar\nbaz\nfoo\n",
		[]string{"*", "dd", ":wq\r"}, 900*time.Millisecond, 400*time.Millisecond)
	if err != nil {
		fmt.Fprintf(out, "  starcheck    * gave no file at all: %v\n", err)
		return ErrReported
	}
	if got != want {
		fmt.Fprintf(out, "  starcheck    * gave %s, expected %s\n", pyRepr(got), pyRepr(want))
		return ErrReported
	}
	return nil
}

// ComplCheck is tools/complcheck.py: insert mode still inserts, and CTRL-X
// CTRL-N no longer completes.
//
// Whim phase 32 stubs the five predicates the completion subsystem hangs from,
// so two things have to be true afterwards and ONLY THE PAIR IS A CHECK:
// ordinary insert mode must be untouched, and the completion key must insert
// nothing rather than completing.  Either half alone would pass on an editor
// that had lost insert mode entirely.
//
// NOT BARE CTRL-N, and this is the measurement that decides it: on the binary
// before the phase, CTRL-N inserts nothing at all in this fork -- the screen
// says `-- INSERT --` and the cursor does not move -- so a check written on it
// passes before and after and proves nothing.  CTRL-X CTRL-N does complete
// today, which is what makes it a check.
func ComplCheck(binary string, out *os.File) error {
	const initial, perKey = 900 * time.Millisecond, 350 * time.Millisecond

	got, err := ptyEditFile(binary, "alpha\nal\n",
		[]string{"G", "A", "X", "\x1b", ":wq\r"}, initial, perKey)
	if err != nil {
		fmt.Fprintf(out, "  complcheck   plain insert gave no file at all: %v\n", err)
		return ErrReported
	}
	if got != "alpha alX " {
		fmt.Fprintf(out, "  complcheck   plain insert gave %s, expected %s\n",
			pyRepr(got), pyRepr("alpha alX "))
		return ErrReported
	}

	got, err = ptyEditFile(binary, "alpha\nal\n",
		[]string{"G", "A", "\x18\x0e", "\x1b", ":wq\r"}, initial, perKey)
	if err != nil {
		fmt.Fprintf(out, "  complcheck   CTRL-X CTRL-N gave no file at all: %v\n", err)
		return ErrReported
	}
	if got != "alpha al " {
		fmt.Fprintf(out, "  complcheck   CTRL-X CTRL-N gave %s, expected %s -- it should "+
			"complete nothing now\n", pyRepr(got), pyRepr("alpha al "))
		return ErrReported
	}
	return nil
}

// TermRestore is tools/termrestore.py: does a killed editor put the terminal
// back?
//
// This is the single thing whim phase 26 keeps SIGHUP and SIGTERM for, and no
// other harness here asks it: the behaviour cases and the Ex sweep run the
// editor to completion, and the pty harness types keys and quits cleanly.  None
// of them kills one halfway and then looks at the terminal.
//
// deathtrap() -> preserve_exit() -> prepare_to_exit() runs settmode(TMODE_COOK),
// which puts ICANON and ECHO back.  If they are still off the user's shell is
// unusable and they have to type `reset` blind, which is a worse failure than a
// crash and the reason the handler is worth its symbols.
//
// IT CARRIES ITS OWN VACUITY GUARD, which is the part worth copying: before
// sending the signal it requires the editor to have really turned raw mode ON.
// Without that the check passes on an editor that never changed anything, which
// is the same shape as a comparison that agrees because it compared nothing.
//
// The binary is NOT staged as `vim` here, unlike the other probes, because the
// Python does not stage it either -- it execs the path it was given.  Fidelity
// to the tool being replaced wins over consistency between the two.
func TermRestore(binary string, out *os.File) error {
	abs, err := filepath.Abs(binary)
	if err != nil {
		return err
	}
	m, slaveName, err := openPty()
	if err != nil {
		return err
	}
	defer m.Close()
	slave, err := os.OpenFile(slaveName, os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		return err
	}

	cmd := exec.Command(abs)
	cmd.Dir = "/tmp"
	cmd.Env = append(os.Environ(), "TERM=xterm")
	cmd.Stdin, cmd.Stdout, cmd.Stderr = slave, slave, slave
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true, Setctty: true}
	if err := cmd.Start(); err != nil {
		slave.Close()
		return err
	}
	slave.Close()
	done := make(chan struct{})
	go func() { cmd.Wait(); close(done) }()

	time.Sleep(1200 * time.Millisecond)
	raw, err := tcGetAttr(m)
	if err != nil {
		fmt.Fprintf(out, "  termrestore  cannot read the pty: %v\n", err)
		cmd.Process.Kill()
		return ErrReported
	}
	if raw.Lflag&syscall.ICANON != 0 || raw.Lflag&syscall.ECHO != 0 {
		fmt.Fprintln(out, "  termrestore  the editor never put the terminal in raw mode, so"+
			" this proves nothing")
		cmd.Process.Kill()
		return ErrReported
	}

	cmd.Process.Signal(syscall.SIGTERM)
	for i := 0; i < 50; i++ {
		time.Sleep(100 * time.Millisecond)
		now, err := tcGetAttr(m)
		if err != nil {
			break
		}
		if now.Lflag&syscall.ICANON != 0 && now.Lflag&syscall.ECHO != 0 {
			return nil
		}
		select {
		case <-done:
			// The child is gone; one last look, because the restore happens on
			// its way out and the poll above may have missed the window.
			if last, err := tcGetAttr(m); err == nil &&
				last.Lflag&syscall.ICANON != 0 && last.Lflag&syscall.ECHO != 0 {
				return nil
			}
		default:
		}
	}
	if cmd.Process != nil {
		cmd.Process.Kill()
	}
	fmt.Fprintln(out, "  termrestore  ICANON/ECHO were still off after SIGTERM")
	return ErrReported
}

// tcGetAttr is termios.tcgetattr on the pty MASTER, through SyscallConn so the
// file stays in the runtime's poller -- Fd() would take it out and a later read
// deadline would silently do nothing.
func tcGetAttr(f *os.File) (*syscall.Termios, error) {
	var t syscall.Termios
	if err := ioctl(f, syscall.TCGETS, unsafe.Pointer(&t)); err != nil {
		return nil, err
	}
	return &t, nil
}
