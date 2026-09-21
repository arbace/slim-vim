package check

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"time"

	"slimvim.local/tools/internal/harness"
)

func z20Env(home string) []string {
	var env []string
	for _, kv := range os.Environ() {
		k := kv[:strings.IndexByte(kv, '=')]
		switch k {
		case "LINES", "COLUMNS", "VIMINIT", "EXINIT", "MYVIMRC", "TERM", "HOME", "VIM", "VIMRUNTIME", "XDG_CONFIG_HOME":
			continue
		}
		env = append(env, kv)
	}
	return append(env, "TERM=xterm", "HOME="+home, "VIM="+home+"/nv",
		"VIMRUNTIME="+home+"/nv", "XDG_CONFIG_HOME="+home+"/xdg")
}

// z20Term is the heredoc's Term: a real pty whose child sets its own window
// size before exec, with stdin optionally at /dev/null and stdout and stderr
// optionally a pipe.  Output is read continuously into out, so a pump is a
// wait and nothing the editor writes is ever left unread.
type z20Term struct {
	cmd  *exec.Cmd
	pid  int
	m    *os.File
	pr   *os.File
	home string
	mu   sync.Mutex
	out  []byte
	done chan *os.ProcessState
	st   *os.ProcessState
	eof  chan struct{}
}

func newZ20Term(binary string, args []string, rows, cols int, stdinDevnull, stdoutPipe bool) (*z20Term, error) {
	vim, err := harness.Stage(binary)
	if err != nil {
		return nil, err
	}
	m, slaveName, err := harness.OpenPty()
	if err != nil {
		return nil, err
	}
	slave, err := os.OpenFile(slaveName, os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		m.Close()
		return nil, err
	}
	defer slave.Close()
	harness.SetWinsize(slave, rows, cols)
	t := &z20Term{m: m, done: make(chan *os.ProcessState, 1)}
	t.home, _ = os.MkdirTemp("", "zero20-")
	c := exec.Command(vim, args...)
	c.Env = z20Env(t.home)
	c.Stdin, c.Stdout, c.Stderr = slave, slave, slave
	ctty := 0
	var pw *os.File
	if stdinDevnull {
		dn, _ := os.Open(os.DevNull)
		defer dn.Close()
		c.Stdin = dn
		ctty = 1
	}
	if stdoutPipe {
		t.pr, pw, _ = os.Pipe()
		c.Stdout, c.Stderr = pw, pw
	}
	c.SysProcAttr = &syscall.SysProcAttr{Setsid: true, Setctty: true, Ctty: ctty}
	if err := c.Start(); err != nil {
		m.Close()
		return nil, err
	}
	if pw != nil {
		pw.Close()
	}
	t.cmd, t.pid = c, c.Process.Pid
	t.eof = make(chan struct{})
	var readers sync.WaitGroup
	for _, f := range []*os.File{t.m, t.pr} {
		if f == nil {
			continue
		}
		readers.Add(1)
		go func(f *os.File) {
			defer readers.Done()
			buf := make([]byte, 65536)
			for {
				n, e := f.Read(buf)
				if n > 0 {
					t.mu.Lock()
					t.out = append(t.out, buf[:n]...)
					t.mu.Unlock()
				}
				if e != nil {
					return
				}
			}
		}(f)
	}
	go func() { readers.Wait(); close(t.eof) }()
	go func() { c.Wait(); t.done <- c.ProcessState }()
	return t, nil
}

// pump waits secs, or less once every descriptor it reads has reached end of
// file -- the heredoc's pump returns as soon as its select set is empty, and
// gs_interrupt's timing is only comparable if this one does too.
func (t *z20Term) pump(secs float64) {
	select {
	case <-time.After(time.Duration(secs * float64(time.Second))):
	case <-t.eof:
	}
}

func (t *z20Term) keys(k string) { t.m.Write([]byte(k)) }

func (t *z20Term) n() int {
	t.mu.Lock()
	defer t.mu.Unlock()
	return len(t.out)
}

func (t *z20Term) mode() string {
	a, err := harness.Termios(t.m)
	if err != nil {
		return "TCGETS " + err.Error()
	}
	b := func(v uint32, f uint32) int {
		if v&f != 0 {
			return 1
		}
		return 0
	}
	return fmt.Sprintf("ICANON=%d ECHO=%d ISIG=%d ONLCR=%d ICRNL=%d",
		b(a.Lflag, syscall.ICANON), b(a.Lflag, syscall.ECHO), b(a.Lflag, syscall.ISIG),
		b(a.Oflag, syscall.ONLCR), b(a.Iflag, syscall.ICRNL))
}

func (t *z20Term) exited() bool {
	if t.st != nil {
		return true
	}
	select {
	case t.st = <-t.done:
		return true
	default:
		return false
	}
}

func (t *z20Term) reap(secs float64) string {
	end := time.Now().Add(time.Duration(secs * float64(time.Second)))
	for time.Now().Before(end) {
		if t.exited() {
			ws := t.st.Sys().(syscall.WaitStatus)
			if ws.Signaled() {
				return fmt.Sprintf("killed by SIG%d", int(ws.Signal()))
			}
			return fmt.Sprintf("exit %d", ws.ExitStatus())
		}
		t.pump(0.05)
	}
	syscall.Kill(t.pid, syscall.SIGKILL)
	if t.st == nil {
		t.st = <-t.done
	}
	return "STILL RUNNING"
}

var z20CSI = regexp.MustCompile(`\x1b\[[0-9;?]*[A-Za-z]`)

func (t *z20Term) text() []byte {
	t.mu.Lock()
	defer t.mu.Unlock()
	return z20CSI.ReplaceAll(append([]byte{}, t.out...), nil)
}

func (t *z20Term) close() {
	t.m.Close()
	if t.pr != nil {
		t.pr.Close()
	}
	os.RemoveAll(t.home)
}

func (t *z20Term) stopped() bool {
	s, err := os.ReadFile(fmt.Sprintf("/proc/%d/stat", t.pid))
	if err != nil {
		return false
	}
	_, rest, ok := strings.Cut(string(s), ") ")
	if !ok {
		return false
	}
	f := strings.Fields(rest)
	return len(f) > 0 && f[0] == "T"
}

type z20Pipe struct {
	text string
	n    int
	rc   int
}

func z20PipeRun(binary string, keys []string, rows, cols, snap int) z20Pipe {
	var kb [][]byte
	for _, k := range keys {
		kb = append(kb, []byte(k))
	}
	scr, out, _, rc, err := harness.ZSession(binary, kb, "xterm", nil, rows, cols, 20*time.Second)
	if err != nil || scr == nil || len(scr.Snaps) == 0 {
		return z20Pipe{"<no snapshot>", len(out), rc}
	}
	k := len(scr.Snaps) + snap
	if len(scr.Snaps) < -snap {
		k = len(scr.Snaps) - 1
	}
	var body []string
	for _, l := range strings.Split(scr.Snaps[k].Text, "\n") {
		s := strings.TrimSpace(l)
		if s != "" && s != "~" {
			body = append(body, strings.TrimRight(l, " \t\r\n\f\v"))
		}
	}
	j := []rune(strings.Join(body, " || "))
	if len(j) > 110 {
		j = j[:110]
	}
	return z20Pipe{string(j), len(out), rc}
}

type z20Deadly struct {
	st, during, after string
	caught, finished  bool
	n                 int
}

type z20Surv struct {
	st       string
	n        int
	aaa, bbb bool
}

type z20Stop struct {
	st    string
	drawn int
	ok    bool
}

type z20EOF struct {
	st  string
	n   int
	fin bool
}

type z20Redir struct {
	st         string
	e492, pmsg bool
}

func z20Deadly1(b string, sig syscall.Signal) any {
	t, err := newZ20Term(b, []string{"+set paste"}, 24, 80, false, false)
	if err != nil {
		return z20Deadly{st: "START"}
	}
	t.pump(1.0)
	t.keys("ihello\x1b")
	t.pump(0.6)
	during := t.mode()
	syscall.Kill(t.pid, sig)
	t.pump(1.2)
	st := t.reap(3.0)
	after := t.mode()
	txt := t.text()
	n := t.n()
	t.close()
	return z20Deadly{st, during, after, bytes.Contains(txt, []byte("Caught deadly signal")), bytes.Contains(txt, []byte("Finished")), n}
}

func z20Survives(b string, how func(*z20Term)) any {
	t, err := newZ20Term(b, []string{"+set paste"}, 24, 80, false, false)
	if err != nil {
		return z20Surv{st: "START"}
	}
	t.pump(1.0)
	t.keys("iAAA\x1b")
	t.pump(0.6)
	how(t)
	t.pump(1.2)
	if t.stopped() {
		syscall.Kill(t.pid, syscall.SIGCONT)
		t.pump(0.6)
	}
	t.keys("iBBB\x1b:q!\r")
	t.pump(1.0)
	st := t.reap(3.0)
	txt := t.text()
	n := t.n()
	t.close()
	return z20Surv{st, n, bytes.Contains(txt, []byte("AAA")), bytes.Contains(txt, []byte("BBB"))}
}

func z20StopCont(b string) any {
	t, err := newZ20Term(b, []string{"+set paste"}, 24, 80, false, false)
	if err != nil {
		return z20Stop{st: "START"}
	}
	t.pump(1.0)
	t.keys("iAAA\x1b")
	t.pump(0.6)
	n0 := t.n()
	syscall.Kill(t.pid, syscall.SIGSTOP)
	t.pump(0.4)
	syscall.Kill(t.pid, syscall.SIGCONT)
	t.pump(1.2)
	drawn := t.n() - n0
	t.keys("iBBB\x1b:q!\r")
	t.pump(1.0)
	st := t.reap(3.0)
	ok := bytes.Contains(t.text(), []byte("BBB"))
	t.close()
	return z20Stop{st, drawn, ok}
}

var z20LinesCols = regexp.MustCompile(`lines=\d+\s+columns=\d+`)

func z20PtyResize(b string) any {
	t, err := newZ20Term(b, []string{"+set paste"}, 24, 80, false, false)
	if err != nil {
		return []string{"START"}
	}
	t.pump(1.0)
	t.keys(":set lines? columns?\r")
	t.pump(0.8)
	harness.SetWinsize(t.m, 30, 100)
	t.pump(1.2)
	t.keys(":set lines? columns?\r")
	t.pump(0.8)
	t.keys(":q!\r")
	t.pump(0.6)
	t.reap(3.0)
	got := []string{}
	for _, m := range z20LinesCols.FindAll(t.text(), -1) {
		got = append(got, strings.Join(strings.Fields(string(m)), " "))
	}
	t.close()
	return got
}

func z20EOFTty2(b string) any {
	t, err := newZ20Term(b, []string{"+set paste"}, 24, 80, true, false)
	if err != nil {
		return z20EOF{st: "START"}
	}
	t.pump(2.5)
	st := t.reap(2.0)
	r := z20EOF{st, t.n(), bytes.Contains(t.text(), []byte("Finished"))}
	t.close()
	return r
}

func z20CtrlCRedir(b string) any {
	t, err := newZ20Term(b, []string{"+set paste"}, 24, 80, false, true)
	if err != nil {
		return z20Redir{st: "START"}
	}
	t.pump(1.0)
	t.keys("\x03")
	t.pump(1.0)
	t.keys(":q!\r")
	t.pump(0.8)
	st := t.reap(3.0)
	txt := t.text()
	r := z20Redir{st, bytes.Contains(txt, []byte("E492")), bytes.Contains(txt, []byte("press <Enter> to exit Vim"))}
	t.close()
	return r
}

func z20RawMode(b string) any {
	t, err := newZ20Term(b, []string{"+set paste"}, 24, 80, false, false)
	if err != nil {
		return "START"
	}
	t.pump(1.0)
	t.keys("ihello\x1b")
	t.pump(0.6)
	m := t.mode()
	t.keys(":q!\r")
	t.pump(0.6)
	t.reap(3.0)
	t.close()
	return m
}

func z20GsInterrupt(b string) any {
	t, err := newZ20Term(b, []string{"+set paste"}, 24, 80, false, false)
	if err != nil {
		return 99.0
	}
	t.pump(1.0)
	t.keys("ihello\x1b")
	t.pump(0.6)
	t.keys("10gs")
	t0 := time.Now()
	t.pump(1.5)
	t.keys("\x03")
	t.pump(0.3)
	t.keys(":q!\r")
	end := time.Now().Add(22 * time.Second)
	got := -1.0
	for time.Now().Before(end) {
		if t.exited() {
			got = time.Since(t0).Seconds()
			break
		}
		t.pump(0.1)
	}
	if got < 0 {
		syscall.Kill(t.pid, syscall.SIGKILL)
		if t.st == nil {
			t.st = <-t.done
		}
		got = 99.0
	}
	t.close()
	return got
}

func pyBool(b bool) string {
	if b {
		return "True"
	}
	return "False"
}

func z20Probes(r *rep, old, bin, nosleep string) error {
	esc := "\x1b"
	type job struct {
		tag string
		fn  func(string) any
	}
	jobs := []job{
		{"resize_inband", func(b string) any {
			return z20PipeRun(b, []string{esc + "[48;30;100t", ":set columns?\r", esc + ":q!\r"}, 40, 200, -2)
		}},
		{"trz_query", func(b string) any { return z20PipeRun(b, []string{":set trz?\r", esc + ":q!\r"}, 40, 200, -2) }},
		{"trz_set", func(b string) any { return z20PipeRun(b, []string{":set trz=sigwinch\r", esc + ":q!\r"}, 40, 200, -2) }},
		{"inband_stop", func(b string) any { return z20PipeRun(b, []string{esc + "[?1z", ":q!\r"}, 24, 80, -1) }},
		{"sigterm", func(b string) any { return z20Deadly1(b, syscall.SIGTERM) }},
		{"sighup", func(b string) any { return z20Deadly1(b, syscall.SIGHUP) }},
		{"sigint_external", func(b string) any {
			return z20Survives(b, func(t *z20Term) { syscall.Kill(t.pid, syscall.SIGINT) })
		}},
		{"tstp_external", func(b string) any {
			return z20Survives(b, func(t *z20Term) { syscall.Kill(t.pid, syscall.SIGTSTP) })
		}},
		{"ctrl_z_key", func(b string) any { return z20Survives(b, func(t *z20Term) { t.keys("\x1a") }) }},
		{"stop_cmd", func(b string) any { return z20Survives(b, func(t *z20Term) { t.keys(":stop\r") }) }},
		{"stopcont", z20StopCont}, {"pty_resize", z20PtyResize},
		{"eof_on_tty2", z20EOFTty2}, {"ctrl_c_redir", z20CtrlCRedir},
		{"raw_mode_live", z20RawMode}, {"gs_interrupt", z20GsInterrupt},
	}
	res := map[[2]string]any{}
	var mu sync.Mutex
	var wg sync.WaitGroup
	launch := func(tag, side, b string, fn func(string) any) {
		wg.Add(1)
		go func() {
			defer wg.Done()
			v := fn(b)
			mu.Lock()
			res[[2]string{tag, side}] = v
			mu.Unlock()
		}()
	}
	for _, j := range jobs {
		launch(j.tag, "old", old, j.fn)
		launch(j.tag, "new", bin, j.fn)
	}
	launch("gs_interrupt", "nosleep", nosleep, z20GsInterrupt)
	wg.Wait()
	g := func(tag, side string) any { return res[[2]string{tag, side}] }
	gp := func(tag, side string) z20Pipe { return g(tag, side).(z20Pipe) }
	var fail []string

	// ---- MUST DIFFER ----
	if strings.Contains(gp("resize_inband", "old").text, "columns=100") || !strings.Contains(gp("resize_inband", "new").text, "columns=100") {
		fail = append(fail, fmt.Sprintf("resize_inband: typing `ESC [ 48;30;100 t` must leave the escape as buffer text on the input and resize the editor to 100 columns on the output.  old=%s new=%s",
			cutilRepr(gp("resize_inband", "old").text), cutilRepr(gp("resize_inband", "new").text)))
	}
	for _, p := range [][2]string{{"trz_query", "trz?"}, {"trz_set", "trz=sigwinch"}} {
		o, n := gp(p[0], "old").text, gp(p[0], "new").text
		if strings.Contains(o, "E518") || !strings.Contains(n, "E518: Unknown option: "+p[1]) {
			fail = append(fail, fmt.Sprintf("%s: `:set %s` must be accepted on the input and E518 on the output -- 'termresize' is the one option this phase removes.  old=%s new=%s", p[0], p[1], cutilRepr(o), cutilRepr(n)))
		}
	}
	if gp("inband_stop", "old").rc == 0 || gp("inband_stop", "new").rc != 0 {
		fail = append(fail, fmt.Sprintf("inband_stop: `ESC [ ? 1 z` is the private sequence the host sends for an external kill -TSTP.  On the input it is not a command and the session ends at end of input (rc 1); on the output it runs `:stop`, comes back and the following `:q!` quits cleanly (rc 0).  old rc=%d new rc=%d", gp("inband_stop", "old").rc, gp("inband_stop", "new").rc))
	}
	eo, en := g("eof_on_tty2", "old").(z20EOF), g("eof_on_tty2", "new").(z20EOF)
	eofRepr := func(e z20EOF) string { return fmt.Sprintf("('%s', %d, %s)", e.st, e.n, pyBool(e.fin)) }
	if eo.st != "STILL RUNNING" || eo.fin || en.st != "exit 1" || !en.fin {
		fail = append(fail, fmt.Sprintf("eof_on_tty2: with stdin at EOF and a TERMINAL on fd 2, the input reopens fd 0 from fd 2 and carries on editing, and the output prints `Vim: Finished.` and exits 1.  This is the ONE behaviour this phase changes.  old=%s new=%s", eofRepr(eo), eofRepr(en)))
	}
	co, cn := g("ctrl_c_redir", "old").(z20Redir), g("ctrl_c_redir", "new").(z20Redir)
	redRepr := func(e z20Redir) string { return fmt.Sprintf("('%s', %s, %s)", e.st, pyBool(e.e492), pyBool(e.pmsg)) }
	if !co.e492 || co.pmsg || cn.e492 || !cn.pmsg {
		fail = append(fail, fmt.Sprintf("ctrl_c_redir: CTRL-C in Normal mode with stdout a pipe ran `do_cmdline_cmd(\"qa\")` on the input (E492, whim having removed :qa) and draws the message on the output, because stdout_isatty is folded to TRUE.  old=%s new=%s", redRepr(co), redRepr(cn)))
	}
	survRepr := func(s z20Surv) string { return fmt.Sprintf("('%s', %d, %s, %s)", s.st, s.n, pyBool(s.aaa), pyBool(s.bbb)) }
	to, tn := g("tstp_external", "old").(z20Surv), g("tstp_external", "new").(z20Surv)
	for _, p := range []struct {
		side string
		s    z20Surv
	}{{"old", to}, {"new", tn}} {
		if p.s.st != "exit 0" || !p.s.aaa || !p.s.bbb {
			fail = append(fail, fmt.Sprintf("tstp_external (%s): the editor must survive kill -TSTP and still be editing afterwards -- %s", p.side, survRepr(p.s)))
		}
	}
	if to.n == tn.n {
		fail = append(fail, fmt.Sprintf("tstp_external: the two streams are the same length (%d).  The input goes through the core's own got_tstp flag and the output through the in-band `ESC [ ? 1 z`, and the byte count is what says it took the new path", to.n))
	}

	// ---- MUST NOT DIFFER ----
	for _, p := range [][2]string{{"sigterm", "TERM"}, {"sighup", "HUP"}} {
		o, n := g(p[0], "old").(z20Deadly), g(p[0], "new").(z20Deadly)
		for _, sr := range []struct {
			side string
			d    z20Deadly
		}{{"old", o}, {"new", n}} {
			d := sr.d
			if d.st != "exit 1" {
				fail = append(fail, fmt.Sprintf("%s (%s): expected `exit 1`, got %s", p[0], sr.side, d.st))
			}
			if d.during != "ICANON=0 ECHO=0 ISIG=0 ONLCR=0 ICRNL=0" {
				fail = append(fail, fmt.Sprintf("%s (%s): the editor was not in raw mode before the signal: %s", p[0], sr.side, d.during))
			}
			if d.after != "ICANON=1 ECHO=1 ISIG=1 ONLCR=1 ICRNL=1" {
				fail = append(fail, fmt.Sprintf("%s (%s): THE TERMINAL WAS NOT RESTORED: %s.  This is the reason the signal phase and the terminal phase were merged: the host installs the core's `deathtrap` rather than replacing it, so deathtrap -> preserve_exit -> prepare_to_exit -> term_leave() still runs", p[0], sr.side, d.after))
			}
			if !d.caught || !d.finished {
				fail = append(fail, fmt.Sprintf("%s (%s): `Vim: Caught deadly signal %s` and `Vim: Finished.` must both be drawn -- got %s, %s", p[0], sr.side, p[1], pyBool(d.caught), pyBool(d.finished)))
			}
		}
		if o.n != n.n {
			fail = append(fail, fmt.Sprintf("%s: the stream is %d bytes on the input and %d on the output, and the deadly path is required to be identical", p[0], o.n, n.n))
		}
	}
	for _, tag := range []string{"sigint_external", "ctrl_z_key", "stop_cmd"} {
		for _, side := range []string{"old", "new"} {
			s := g(tag, side).(z20Surv)
			if s.st != "exit 0" || !s.aaa || !s.bbb {
				fail = append(fail, fmt.Sprintf("%s (%s): the editor must survive and still be editing afterwards -- %s", tag, side, survRepr(s)))
			}
		}
	}
	ro, rn := g("raw_mode_live", "old").(string), g("raw_mode_live", "new").(string)
	if ro != rn || rn != "ICANON=0 ECHO=0 ISIG=0 ONLCR=0 ICRNL=0" {
		fail = append(fail, fmt.Sprintf("raw_mode_live: the terminal while the editor is editing must be raw on both -- old=%s new=%s", cutilRepr(ro), cutilRepr(rn)))
	}
	for _, side := range []string{"old", "new"} {
		got := g("pty_resize", side).([]string)
		if strings.Join(got, "|") != "lines=24 columns=80|lines=30 columns=100" || len(got) != 2 {
			q := make([]string, len(got))
			for i, v := range got {
				q[i] = cutilRepr(v)
			}
			fail = append(fail, fmt.Sprintf("pty_resize (%s): a 24x80 pty resized to 30x100 must be seen -- got [%s].  On the output this is the WHOLE in-band path: the host catches SIGWINCH, its ioctl reads the new size, musl_read_input hands the core `CSI 48;30;100;0;0t`, and handle_csi resizes", side, strings.Join(q, ", ")))
		}
	}
	for _, side := range []string{"old", "new"} {
		s := g("stopcont", side).(z20Stop)
		if s.st != "exit 0" || !s.ok || s.drawn < 1000 {
			fail = append(fail, fmt.Sprintf("stopcont (%s): after kill -STOP; kill -CONT the editor must redraw its screen and still be editing -- got %s, %d bytes drawn, BBB=%s.  On the output that redraw is the host catching SIGCONT with the same handler as SIGWINCH, which is why the CSI 48 arm lost its `height != Rows` guard", side, s.st, s.drawn, pyBool(s.ok)))
		}
	}
	gs := func(side string) float64 { return g("gs_interrupt", side).(float64) }
	for _, side := range []string{"old", "new"} {
		if gs(side) > 6.0 {
			fail = append(fail, fmt.Sprintf("gs_interrupt (%s): `10gs` then CTRL-C after 1.5 s must come back in about 1.8 s and took %.2f s", side, gs(side)))
		}
	}
	if gs("nosleep") < 15.0 {
		fail = append(fail, fmt.Sprintf("THE CONTROL RECOVERED.  This phase's own output with musl_delay()'s two host_tty_set() calls deleted took %.2f s, and the whole point of the sleep mode is that WITHOUT it the interrupt character is a plain byte in the input queue and the nanosleep runs to its full ten seconds.  Two numbers agreeing prove nothing if a wrong one is not caught", gs("nosleep")))
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	r.say("MUST DIFFER (7): resize_inband -- `ESC[48;30;100t` is buffer text on the input and `columns=100` here; trz_query and trz_set -- `:set trz?` and `:set trz=sigwinch` are accepted on the input and E518 here; inband_stop -- `ESC[?1z` is nothing on the input and runs `:stop` here (rc %d -> %d); eof_on_tty2 -- with a terminal on fd 2 the input reopens fd 0 and keeps editing (%d B) where this prints `Vim: Finished.` and exits 1 (%d B); ctrl_c_redir -- CTRL-C with stdout a pipe was E492 and is the message; tstp_external -- %d B against %d B, the in-band path",
		gp("inband_stop", "old").rc, gp("inband_stop", "new").rc, eo.n, en.n, to.n, tn.n)
	dt, dh := g("sigterm", "new").(z20Deadly), g("sighup", "new").(z20Deadly)
	r.cont("MUST NOT DIFFER, and these are the ones the merge was for: kill -TERM and kill -HUP both exit 1, both restore the terminal to %s, both draw `Vim: Caught deadly signal` and `Vim: Finished.`, and both streams are the same length (%d and %d bytes)", dt.after, dt.n, dh.n)
	r.cont("and: kill -INT survives on both (the host hands the core a 0x03 byte, where SIG_DFL would KILL it); keyboard CTRL-Z and `:stop` both come back editing; the terminal is raw while editing on both (%s); a 24x80 pty resized to 30x100 is seen by both; kill -STOP/-CONT redraws %d bytes on the input and %d here",
		rn, g("stopcont", "old").(z20Stop).drawn, g("stopcont", "new").(z20Stop).drawn)
	r.cont("gs_interrupt, WITH ITS CONTROL: `10gs` then CTRL-C comes back at %.2f s on the input and %.2f s here -- and at %.2f s on this phase's own output with musl_delay()'s two host_tty_set() calls deleted.  That is what says the sleep mode is real: TMODE_SLEEP is not \"discard input\", it is the saved termios with ICANON and ECHO cleared and ISIG LEFT ON, so the interrupt character is a signal for the duration of the sleep",
		gs("old"), gs("new"), gs("nosleep"))
	return nil
}
