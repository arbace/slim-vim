package harness

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strings"
	"syscall"
	"time"
)

const showCursor = "\x1b[?25h"

// zptyModes are every mode the editor announces on the message line.  Which of
// them a scenario entered is a fact about the editor, and sel_arrows is a
// scenario whose WHOLE ANSWER is one of them.
var zptyModes = []string{"VISUAL", "SELECT", "INSERT", "REPLACE"}

var (
	zEsc    = "\x1b"
	zDown   = zEsc + "[B"
	zRight  = zEsc + "[C"
	zSRight = zEsc + "[1;2C"
)

var zptyScenarios = []struct {
	name       string
	rows, cols int
	term       string
	keys       []string
}{
	{"size_24x80", 24, 80, "xterm", []string{":set lines? columns?\r", "\x1b:q!\r"}},
	{"size_30x100", 30, 100, "xterm", []string{":set lines? columns?\r", "\x1b:q!\r"}},
	{"raw_typing", 24, 80, "xterm", []string{"ihello world", zEsc, ":set term?\r", "\x1b:q!\r"}},
	{"nav_arrows", 24, 80, "xterm", []string{"il1\rl2\rl3", zEsc, "gg", zDown + zDown + zRight,
		"x", "\x1b:q!\r"}},
	// Two SHIFTED rights on `alpha one` select `alp` under 'keymodel'=startsel,
	// so `x` leaves `ha one`; without the flag they are two `w` motions and `x`
	// leaves `alpha ne`.  Both the mode and the text move, together.
	{"sel_arrows", 24, 80, "xterm", []string{"ialpha one", zEsc, "0", zSRight + zSRight,
		"x", "\x1b:q!\r"}},
}

// ZPty records the five pty scenarios: the window size, raw mode, and a
// modified key.
//
// A PTY HARNESS WAITS ON CONTENT, NEVER ON A CLOCK.  It used to type the next
// key once output had been quiet for 0.25 s, which is a reading of the
// machine's LOAD: under enough of one the editor stalls mid-redraw, the key
// goes in early, and the answer the scenario asked for is wiped before any
// redraw ends on it.  It now waits for one more show-cursor -- which is where
// a redraw ENDS, and where the screen model snapshots -- and only then asks
// about quiet.  Measured under one oscillating 192-way load: 16 of 60 runs
// failed before, 0 of 60 after.
func ZPty(bin, out string, w io.Writer) error {
	var rows []string
	var bad []string
	for _, sc := range zptyScenarios {
		scr, status, stalled, err := zptySession(bin, sc.rows, sc.cols, sc.term, sc.keys,
			250*time.Millisecond, 60*time.Second)
		if err != nil {
			return err
		}
		got, body := zptyAnswers(scr)
		row := "=== " + sc.name + "\n"
		row += Section(fmt.Sprintf("pty %dx%d TERM=%s status=%s",
			sc.rows, sc.cols, sc.term, status), nil)
		gotBody := strings.Join(got, " ")
		row += Section("answers", &gotBody)
		textBody := strings.Join(body, " | ")
		row += Section("text", &textBody)
		// A WAIT THAT REACHED ITS DEADLINE SAYS SO, in the record and on
		// stderr and in the exit status.  Returning the short capture silently
		// is what made this a recording of the machine's load.
		if len(stalled) > 0 {
			s := strings.Join(stalled, "; ")
			row += Section("stalled", &s)
			bad = append(bad, sc.name+": "+s)
		}
		rows = append(rows, Scrub(row))
	}
	if err := os.WriteFile(out, []byte(strings.Join(rows, "")), 0o644); err != nil {
		return err
	}
	if len(bad) > 0 {
		fmt.Fprintf(os.Stderr, "zpty: NO REDRAW ENDED INSIDE THE DEADLINE -- this "+
			"recording is of the machine and not of %s\n", bin)
		for _, b := range bad {
			fmt.Fprintf(os.Stderr, "  %s\n", b)
		}
		return fmt.Errorf("zpty: stalled")
	}
	fmt.Fprintf(w, "%d pty scenarios -> %s\n", len(zptyScenarios), out)
	return nil
}

func zptySession(bin string, rows, cols int, term string, keys []string,
	quiet, timeout time.Duration) (*Screen, string, []string, error) {

	vim, err := Stage(bin)
	if err != nil {
		return nil, "", nil, err
	}
	home, err := os.MkdirTemp("", "zpty-home-")
	if err != nil {
		return nil, "", nil, err
	}
	defer os.RemoveAll(home)

	m, slaveName, err := openPty()
	if err != nil {
		return nil, "", nil, err
	}
	defer m.Close()
	slave, err := os.OpenFile(slaveName, os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		return nil, "", nil, err
	}

	// THE WINDOW SIZE IS SET BEFORE THE CHILD EXECS.  Setting it on the master
	// after a fork is a bet that the parent beats the child's startup, and
	// losing it leaves a 24-row scroll region on a 30-row screen where three
	// message lines overwrite each other on the bottom row.
	ws := winsize{rows: uint16(rows), cols: uint16(cols)}
	ioctl(slave, syscall.TIOCSWINSZ, unsafePointerOf(&ws))

	cmd := exec.Command(vim)
	cmd.Env = append(Env(home), "TERM="+term)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = slave, slave, slave
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true, Setctty: true}
	if err := cmd.Start(); err != nil {
		slave.Close()
		return nil, "", nil, err
	}
	slave.Close()

	if err := m.SetReadDeadline(time.Now().Add(time.Second)); err != nil {
		return nil, "", nil, fmt.Errorf("zpty: the master takes no read deadline (%v)", err)
	}

	scr := NewScreen(rows, cols)
	var seen []byte // every byte, only to count the redraws in it
	deadline := time.Now().Add(timeout)
	var stalled []string
	buf := make([]byte, 65536)

	readOnce := func() bool {
		m.SetReadDeadline(time.Now().Add(20 * time.Millisecond))
		n, err := m.Read(buf)
		if n > 0 {
			seen = append(seen, buf[:n]...)
			scr.Feed(buf[:n])
		}
		if err != nil {
			if os.IsTimeout(err) {
				return true
			}
			return false // the master gives EIO once the editor is gone
		}
		return true
	}

	// settle waits for one more redraw to END, and only then for the output to
	// stop.  The content half is the whole of the fix: a quiet period alone is
	// a reading of the machine's load, and asking about it before a redraw has
	// ended is what typed the next key into a screen still being drawn.
	settle := func(what string) bool {
		want := bytes.Count(seen, []byte(showCursor)) + 1
		last := time.Now()
		for {
			n := len(seen)
			alive := readOnce()
			if len(seen) > n {
				last = time.Now()
			}
			if !alive {
				return false
			}
			now := time.Now()
			if bytes.Count(seen, []byte(showCursor)) >= want && now.Sub(last) > quiet {
				return true
			}
			if now.After(deadline) {
				stalled = append(stalled, what)
				return true
			}
		}
	}

	alive := settle("startup")
	for i, k := range keys {
		if !alive {
			break
		}
		if _, err := m.Write([]byte(k)); err != nil {
			break
		}
		alive = settle(fmt.Sprintf("key %d (%s)", i, pyBytesRepr(k)))
	}
	for alive && !time.Now().After(deadline) {
		alive = readOnce()
	}

	status := "GONE"
	if alive {
		stalled = append(stalled, "exit")
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
	}
	if err := cmd.Wait(); err != nil || cmd.ProcessState != nil {
		if cmd.ProcessState != nil {
			if ws, ok := cmd.ProcessState.Sys().(syscall.WaitStatus); ok {
				status = fmt.Sprint(waitStatusInt(ws))
			}
		}
	}
	return scr, status, stalled, nil
}

// waitStatusInt is the integer Python's os.waitpid returns: the exit code in
// the high byte, or the signal number in the low one.
func waitStatusInt(ws syscall.WaitStatus) int {
	if ws.Signaled() {
		return int(ws.Signal())
	}
	return ws.ExitStatus() << 8
}

func zptyAnswers(scr *Screen) ([]string, []string) {
	// EVERY SNAPSHOT IS SEARCHED, not the final screen: the keys that quit
	// wipe the message line, so a :set answer lives in the redraw before them
	// and nowhere else.
	var all []string
	for _, s := range scr.Snaps {
		all = append(all, s.Text)
	}
	all = append(all, scr.Dump())
	text := strings.Join(all, "\n")

	var out []string
	for _, pat := range []string{`lines=\d+`, `columns=\d+`, `term=[\w.+-]+`} {
		re := regexp.MustCompile(pat)
		seen := map[string]bool{}
		var hits []string
		for _, m := range re.FindAllString(text, -1) {
			if !seen[m] {
				seen[m] = true
				hits = append(hits, m)
			}
		}
		sort.Strings(hits)
		out = append(out, hits...)
	}
	for _, mode := range zptyModes {
		if strings.Contains(text, "-- "+mode+" --") {
			out = append(out, "mode="+mode)
		}
	}
	var body []string
	for _, l := range strings.Split(scr.Dump(), "\n") {
		t := strings.TrimSpace(l)
		if t != "" && t != "~" {
			body = append(body, l)
		}
	}
	if len(body) > 3 {
		body = body[:3]
	}
	return out, body
}

// pyBytesRepr is Python's repr() of a bytes object, which the stalled label
// carries into the record.
func pyBytesRepr(s string) string {
	var b strings.Builder
	b.WriteString("b'")
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '\\':
			b.WriteString(`\\`)
		case c == '\'':
			b.WriteString(`\'`)
		case c == '\n':
			b.WriteString(`\n`)
		case c == '\r':
			b.WriteString(`\r`)
		case c == '\t':
			b.WriteString(`\t`)
		case c >= 0x20 && c < 0x7f:
			b.WriteByte(c)
		default:
			fmt.Fprintf(&b, `\x%02x`, c)
		}
	}
	b.WriteString("'")
	return b.String()
}
