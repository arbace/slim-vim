package check

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"slimvim.local/tools/internal/cutil"
	"slimvim.local/tools/internal/harness"
)

func init() { register("zero2", Zero2) }

// z2Gone is what the cut removed, matched as FIXED strings because two of them
// are C fragments with parentheses in.
var z2Gone = []string{
	"tty_fail", "ttyfail",
	"Vim: Warning: Output is not to a terminal",
	"Vim: Warning: Input is not from a terminal",
	"ui_delay(2005L",
}

// z2Kept is what the phase deliberately keeps, each with the reader that forces
// it.  A sweep that took one of these would leave the editor silently different
// rather than fail to build, which is why they are asserted rather than trusted.
var z2Kept = []struct{ needle, why string }{
	{"^check_tty(void)$", "check_tty(void) is gone"},
	{"^    check_tty();$", "nothing calls check_tty()"},
}

var z2KeptBody = []struct{ needle, why string }{
	{"input_isatty = mch_input_isatty();", "check_tty no longer asks mch_input_isatty()"},
	{"if (exmode_active)", "the exmode_active branch went -- Ex mode is a later phase, not this one"},
	{"silent_mode = TRUE;", "Ex mode no longer goes silent when its input is not a terminal"},
}

var z2KeptFile = []struct{ needle, why string }{
	{"int out_redir = !stdout_isatty;", "stdout_isatty lost the reader that keeps it, and mch_check_win, alive"},
	{"stdout_isatty = (mch_check_win(", "nothing assigns stdout_isatty any more"},
}

// occurrences counts MATCHES and not lines.  `grep -c` counts matching lines,
// and `!isatty(fd) && isatty(read_cmd_fd)` puts two calls on one -- which is how
// the five isatty calls first read as four and failed a check that was right.
func occurrences(pat string, src []byte) int {
	return len(regexp.MustCompile(pat).FindAll(src, -1))
}

// Zero2 is phase 2's check: the two terminal warnings, the pause after them and
// --ttyfail.
//
// THE PROBES ARE THIS PHASE'S EVIDENCE and they are two-sided.  The three
// harnesses tools/zerodelta.sh runs cannot see this cut at all -- behaviour and
// exsweep run the editor `-e -s`, where exmode_active takes check_tty()'s first
// branch, and termcheck drives a real pty where neither stream is a file.  So
// the declared delta is legitimately none, and a delta of none from a blind
// harness proves nothing on its own.  Every probe requires the OLD binary to do
// the thing and the new one not to.
func Zero2(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero2 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "nottywarn", w: w}
	f := filepath.Join(work, "zero-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	src, err := os.ReadFile(f)
	if err != nil {
		return err
	}
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }

	// --- 1. what the cut removed ---------------------------------------------
	for _, g := range z2Gone {
		if n := bytes.Count(src, []byte(g)); n != 0 {
			return stop("'%s' still has %d mentions", g, n)
		}
	}
	if n := occurrences(`\bui_delay\(`, src); n != 10 {
		return stop("ui_delay is named %d times, expected 10 (8 calls, a prototype and the definition)", n)
	}

	// --- 2. what it deliberately kept ----------------------------------------
	// LITERAL LINES, not patterns.  The shell asks these with `grep -q`, where
	// basic regular expressions leave `(` and `)` as ordinary characters, so
	// `^check_tty(void)$` means that line.  Compiled as an RE2 pattern the
	// parentheses are a GROUP and the same string means `check_ttyvoid` --
	// which is a check that cannot pass, and did not.
	for _, k := range z2Kept {
		line := strings.TrimSuffix(strings.TrimPrefix(k.needle, "^"), "$")
		if !hasLine(src, line) {
			return stop("%s", k.why)
		}
	}
	body := awkRange(src, `^check_tty\(void\)$`, `^\}$`)
	for _, k := range z2KeptBody {
		if !strings.Contains(body, k.needle) {
			return stop("%s", k.why)
		}
	}
	for _, k := range z2KeptFile {
		if !bytes.Contains(src, []byte(k.needle)) {
			return stop("%s", k.why)
		}
	}
	if n := occurrences(`\bisatty\(`, src); n != 5 {
		return stop("isatty is called %d times, expected the same 5: this phase folds no isatty caller", n)
	}
	if !bytes.Contains(src, []byte("if (params.want_full_screen && !silent_mode)")) {
		return stop("want_full_screen lost its surviving reader")
	}
	scan := awkRange(src, `^command_line_scan\(mparm_T`, `^\}$`)
	if n := strings.Count(scan, "had_minmin = TRUE;"); n != 1 {
		return stop("'--' sets had_minmin %d times, expected once", n)
	}
	r.say("kept: the exmode branch, mch_input_isatty, stdout_isatty's reader, mch_check_win, all 5 isatty calls")

	// --- 3. the compile, the linkage and the libc surface --------------------
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}

	// --- 4. the binary -------------------------------------------------------
	// NOT tools/phasebuild.sh, which links the object the sweep compiled along
	// the way: that object is `gcc -c -O0` with this machine's defaults, which
	// since phase 1 are not zero's -- it carries the canaries
	// -fno-stack-protector removes and PIE code where the link is -no-pie.
	_ = exec.Command("make", "-C", work, "clean").Run()
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		rp := &rep{tag: "build", w: w}
		rp.say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	bin := filepath.Join(work, "zero-vim")
	now, _ := os.ReadFile(f)
	(&rep{tag: "build", w: w}).say("ok, %s -> %d lines, %d bytes",
		beforeLines, bytes.Count(now, []byte("\n")), sizeOf(bin))

	// --- 5. the probes -------------------------------------------------------
	d, err := os.MkdirTemp("", "zero2")
	if err != nil {
		return err
	}
	defer os.RemoveAll(d)
	for _, s := range []string{"h", "old", "new"} {
		os.MkdirAll(filepath.Join(d, s), 0o755)
	}
	// Staged as `vim` under both names: a vim reads its own argv[0], and a
	// basename starting with r, e, g or the view/ex prefixes is a different
	// editor.
	copyExec(filepath.Join(state, "old"), filepath.Join(d, "old", "vim"))
	copyExec(bin, filepath.Join(d, "new", "vim"))
	keys := []byte("ihello world\x1b:q!\r")
	os.WriteFile(filepath.Join(d, "keys"), keys, 0o644)

	// No -u NONE: an empty $HOME, $VIM, $VIMRUNTIME and $XDG_CONFIG_HOME are
	// the isolation, as in every harness here.
	env := z2Env(filepath.Join(d, "h"))
	runSide := func(side string, in []byte, argv ...string) (int, []byte, []byte, int64) {
		c := exec.Command("./vim", argv...)
		c.Dir = filepath.Join(d, side)
		c.Env = env
		var out, errb bytes.Buffer
		c.Stdout, c.Stderr = &out, &errb
		if in != nil {
			c.Stdin = bytes.NewReader(in)
		}
		t0 := time.Now()
		rc := 0
		if e := c.Run(); e != nil {
			rc = exitCode(e)
		}
		ms := time.Since(t0).Milliseconds()
		return rc, out.Bytes(), errb.Bytes(), ms
	}

	// 5a.  stdin a file of keystrokes, stdout a file: the case the warnings
	// were for.
	type res struct {
		rc       int
		out, err []byte
		ms       int64
	}
	got := map[string]res{}
	for _, side := range []string{"old", "new"} {
		os.WriteFile(filepath.Join(d, side, "f.txt"), []byte("one\ntwo\nthree\n"), 0o644)
		rc, out, errb, ms := runSide(side, keys, "f.txt")
		got[side] = res{rc, out, errb, ms}
	}
	for _, side := range []string{"old", "new"} {
		if got[side].rc != 0 {
			return stop("the %s binary exited %d on a redirected run, expected 0", side, got[side].rc)
		}
	}
	// The old binary must warn and must pause, or the two requirements below
	// could not fail.
	for _, want := range []string{"Output is not to a terminal", "Input is not from a terminal"} {
		if !bytes.Contains(got["old"].err, []byte(want)) {
			return stop("the input binary did not print '%s' -- the check below proves nothing", want)
		}
	}
	if got["old"].ms < 1500 {
		return stop("the input binary took %dms, so it did not pause -- the timing check proves nothing", got["old"].ms)
	}
	if len(got["new"].err) > 0 {
		r.say("stderr is not empty after the cut:")
		for _, l := range strings.Split(strings.TrimRight(string(got["new"].err), "\n"), "\n") {
			r.cont("  %s", l)
		}
		return harness.ErrReported
	}
	if got["new"].ms > 500 {
		return stop("the redirected run still takes %dms, expected under 500 with the pause gone", got["new"].ms)
	}
	if !bytes.Equal(got["old"].out, got["new"].out) {
		r.say("the escape stream MOVED: %d -> %d bytes", len(got["old"].out), len(got["new"].out))
		r.cont("only the warnings and the pause were to go, not what is drawn")
		return harness.ErrReported
	}
	if pipeJoin(readFile(filepath.Join(d, "new", "f.txt"))) != "one|two|three|" {
		return stop(":q! wrote the file")
	}
	r.say("redirected: stderr %d -> 0 bytes, %dms -> %dms, the %d-byte stream byte-identical",
		len(got["old"].err), got["old"].ms, got["new"].ms, len(got["new"].out))

	// 5b.  --ttyfail is now an unknown option.  Both binaries exit 1 -- the old
	// because the flag asked it to, the new because the flag does not exist --
	// so the status is not the check; what mainerr() prints is.
	tf := map[string][]byte{}
	for _, side := range []string{"old", "new"} {
		os.WriteFile(filepath.Join(d, side, "t.txt"), []byte("one\ntwo\n"), 0o644)
		rc, _, errb, _ := runSide(side, []byte{}, "--ttyfail", "t.txt")
		if rc != 1 {
			return stop("the %s binary exited %d on --ttyfail, expected 1", side, rc)
		}
		tf[side] = errb
	}
	const unknown = `Unknown option argument: "--ttyfail"`
	if bytes.Contains(tf["old"], []byte(unknown)) {
		return stop("the input binary already rejected --ttyfail -- this check proves nothing")
	}
	if !bytes.Contains(tf["new"], []byte(unknown)) {
		r.say("--ttyfail is not an unknown option:")
		for _, l := range strings.Split(strings.TrimRight(string(tf["new"]), "\n"), "\n") {
			r.cont("  %s", l)
		}
		return harness.ErrReported
	}

	// 5c.  the rest of that switch case, and the two argument forms next to it,
	// still work -- the same result from both binaries.
	for _, side := range []string{"old", "new"} {
		os.WriteFile(filepath.Join(d, side, "-x.txt"), []byte("z\n"), 0o644)
		rc, _, _, _ := runSide(side, []byte{}, "-e", "-s", "+1", "+normal! A-dd", "+wq", "--", "-x.txt")
		if rc != 0 {
			return stop("'--' as end of options exited %d on the %s binary", rc, side)
		}
		if pipeJoin(readFile(filepath.Join(d, side, "-x.txt"))) != "z-dd|" {
			return stop("'--' stopped ending the options on the %s binary", side)
		}

		os.WriteFile(filepath.Join(d, side, "c.txt"), []byte("one\ntwo\n"), 0o644)
		rc, _, _, _ = runSide(side, keys, "+normal! A-PLUS", "+wq", "c.txt")
		if rc != 0 {
			return stop("+cmd exited %d on the %s binary", rc, side)
		}
		if g := pipeJoin(readFile(filepath.Join(d, side, "c.txt"))); g != "one-PLUS|two|" {
			return stop("+cmd broke on the %s binary: '%s'", side, g)
		}

		os.WriteFile(filepath.Join(d, side, "T.txt"), []byte("one\ntwo\n"), 0o644)
		rc, _, _, _ = runSide(side, keys, "-T", "dumb", "+normal! A-T", "+wq", "T.txt")
		if rc != 0 {
			return stop("-T exited %d on the %s binary", rc, side)
		}
		if g := pipeJoin(readFile(filepath.Join(d, side, "T.txt"))); g != "one-T|two|" {
			return stop("-T broke on the %s binary: '%s'", side, g)
		}
	}
	r.say("--ttyfail is mainerr'd, '--', +cmd and -T unchanged on both binaries")

	// 5d.  a real terminal, where nothing here was ever reached: the same
	// session under both binaries.  termcheck drives 19 of these in the
	// declared delta; this one is the before-and-after the delta cannot give,
	// because it has no old binary.
	oldS, e1 := z2Pty(filepath.Join(state, "old"))
	newS, e2 := z2Pty(bin)
	if e1 != nil {
		return e1
	}
	if e2 != nil {
		return e2
	}
	for _, p := range []struct {
		name string
		s    z2Sess
	}{{"old", oldS}, {"new", newS}} {
		if p.s.status != 0 || p.s.file != "alpha one\nbeta two-typed\n" || !p.s.typed || len(p.s.term) == 0 {
			return stop("the pty session broke on the %s binary: status=%d file=%s term=%s typed=%v",
				p.name, p.s.status, cutil.PyRepr(p.s.file), z2List(p.s.term), p.s.typed)
		}
	}
	if !oldS.eq(newS) {
		return stop("the pty session moved: %s -> %s", oldS.repr(), newS.repr())
	}
	// The `term=` answer is not printed: the ruler follows it on the same
	// screen line, so what comes back reads like a terminal name that does not
	// exist.  What it is here for is the comparison, which is exact.
	r.say("pty: status 0, the typed text on screen and in the file, the same term answer either side")
	return nil
}

type z2Sess struct {
	status int
	file   string
	term   []string
	typed  bool
}

func (a z2Sess) eq(b z2Sess) bool {
	return a.status == b.status && a.file == b.file && a.typed == b.typed && z2List(a.term) == z2List(b.term)
}

func (a z2Sess) repr() string {
	return fmt.Sprintf("(%d, %s, %s, %v)", a.status, cutil.PyRepr(a.file), z2List(a.term), a.typed)
}

func z2List(s []string) string {
	q := make([]string, len(s))
	for i, v := range s {
		q[i] = cutil.PyRepr(v)
	}
	return "[" + strings.Join(q, ", ") + "]"
}

var z2Term = regexp.MustCompile(`term=[\w.-]+`)

func z2Pty(binary string) (z2Sess, error) {
	home, err := os.MkdirTemp("", "zero2-home-")
	if err != nil {
		return z2Sess{}, err
	}
	d, err := os.MkdirTemp("", "zero2-pty-")
	if err != nil {
		return z2Sess{}, err
	}
	os.WriteFile(filepath.Join(d, "f.txt"), []byte("alpha one\nbeta two\n"), 0o644)
	text, status, err := harness.Session(binary, []string{"f.txt"},
		[][]byte{[]byte("GA-typed"), []byte("\x1b"), []byte(":set term?\r"), []byte(":wq\r")},
		"xterm", 20*time.Second, 600*time.Millisecond, d, z2Env(home), 0, 0)
	if err != nil {
		return z2Sess{}, err
	}
	s := string(text)
	// The two answers land among the '~' filler and the cursor keeps moving
	// through them, so take the name and nothing after it, as termcheck does.
	seen := map[string]bool{}
	for _, m := range z2Term.FindAllString(s, -1) {
		seen[m] = true
	}
	out := make([]string, 0, len(seen))
	for k := range seen {
		out = append(out, k)
	}
	sort.Strings(out)
	return z2Sess{status, readFile(filepath.Join(d, "f.txt")), out, strings.Contains(s, "-typed")}, nil
}

func z2Env(home string) []string {
	env := []string{}
	for _, kv := range os.Environ() {
		k := kv[:strings.IndexByte(kv, '=')]
		switch k {
		case "VIMINIT", "EXINIT", "MYVIMRC", "HOME", "VIM", "VIMRUNTIME", "XDG_CONFIG_HOME", "TERM":
			continue
		}
		env = append(env, kv)
	}
	return append(env,
		"HOME="+home,
		"VIM="+filepath.Join(home, "novim"),
		"VIMRUNTIME="+filepath.Join(home, "novim"),
		"XDG_CONFIG_HOME="+filepath.Join(home, "xdg"),
		"TERM=xterm")
}
