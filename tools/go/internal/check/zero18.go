package check

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"time"

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero18", Zero18) }

const (
	z18Head   = "\n    int\nmain\n(int argc, char **argv)\n{\n"
	z18Launch = "\n    int\nmain(int argc, char **argv)\n{\n    return vim_main(argc, argv);\n}\n"
)

// Zero18 is phase 18's check: main() demoted to a static vim_main(), with a
// six-line launcher appended below it.
func Zero18(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero18 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "demote", w: w}
	f := filepath.Join(work, "zero-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	tmp, err := os.MkdirTemp("", "zero18")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	newC, oldC := readFile(f), readFile(filepath.Join(state, "old.c"))

	// --- 1. the control build, started first because it is the slowest ------
	// ONE CHARACTER: mch_exit's `exit(r)` becomes `exit(r + 1)`.  Six statuses
	// that agree prove nothing unless a wrong one would have been caught.
	off := strings.ReplaceAll(newC, "\n    exit(r);\n", "\n    exit(r + 1);\n")
	if off == newC {
		return stop("the control edit changed nothing -- mch_exit's `exit(r);` is not where this phase expects it")
	}
	if strings.Count(off, "\n    exit(r + 1);\n") != 1 {
		return stop("the control edit did not land exactly once")
	}
	offC := filepath.Join(tmp, "off.c")
	os.WriteFile(offC, []byte(off), 0o644)
	mk := readFile(filepath.Join(work, "Makefile"))
	flags := append(strings.Fields(z9Flag(mk, "CFLAGS")), strings.Fields(z9Flag(mk, "LDFLAGS"))...)
	offBin := filepath.Join(tmp, "off")
	offDone := make(chan error, 1)
	go func() {
		offDone <- exec.Command("gcc", append(append([]string{}, flags...), "-o", offBin, offC)...).Run()
	}()

	// --- 2. the source -------------------------------------------------------
	var fail []string
	mentions := func(t, name string) int {
		return len(regexp.MustCompile(`\b` + regexp.QuoteMeta(name) + `\b`).FindAllString(t, -1))
	}
	runs := func(t string) int {
		L := strings.Split(t, "\n")
		n := 0
		for i := 1; i < len(L); i++ {
			if L[i] == "" && L[i-1] == "" {
				n++
			}
		}
		return n
	}
	if strings.Count(oldC, z18Head) != 1 {
		fail = append(fail, "the input did not hold exactly one three-line main() head, so this is not the file the phase was written against")
	}
	if mentions(oldC, "vim_main") > 0 {
		fail = append(fail, "`vim_main` was already a word in the input, and this phase introduces it")
	}
	if strings.Count(newC, "    static int\nvim_main(int argc, char **argv)\n{\n") != 1 {
		fail = append(fail, "the output does not define `static int vim_main(int argc, char **argv)` exactly once.  It must be STATIC: nothing outside this file calls it, and a non-static one would be the first external symbol zero has ever added")
	}
	if strings.Contains(newC, z18Head) {
		fail = append(fail, "main()'s three-line head survives in the output")
	}
	if !strings.HasSuffix(newC, z18Launch) {
		fail = append(fail, "zero-vim.c does not end with the six-line launcher.  CLAUDE.md states that main() is literally the last thing in this file and its closing brace the final line, and that stays true")
	}
	if n := strings.Count(newC, z18Launch); n != 1 {
		fail = append(fail, fmt.Sprintf("the launcher occurs %d times, expected 1", n))
	}
	for _, p := range []struct {
		name string
		want int
		why  string
	}{
		{"main", 1, "the launcher's head, and it is the ONLY bare `main` in 80,000 lines -- `main_loop`, `main_errors`, `vim_main` and `vim_main2` are different words"},
		{"vim_main", 2, "its definition and the one call from the launcher.  A third would be a prototype, and a function defined above its only call needs none"},
		{"vim_main2", 2, "upstream's second half of main(): its definition and the call at the end of vim_main().  This phase does not touch it"},
	} {
		if mentions(newC, p.name) != p.want {
			fail = append(fail, fmt.Sprintf("`%s` as a whole word has %d mentions, expected %d -- %s", p.name, mentions(newC, p.name), p.want, p.why))
		}
	}
	if strings.Count(newC, "    static int\nvim_main2(void)\n{\n") != 1 {
		fail = append(fail, "vim_main2() moved, and this phase does not touch it")
	}
	if !regexp.MustCompile(`\n    return vim_main2\(\);\n\}\n\n    int\nmain`).MatchString(newC) {
		fail = append(fail, "vim_main() does not end in `return vim_main2();` immediately above the launcher -- the body is meant to be untouched and the launcher appended after it")
	}
	if d := len(strings.Split(newC, "\n")) - len(strings.Split(oldC, "\n")); d != 5 {
		fail = append(fail, fmt.Sprintf("the file gained %d lines, expected 5 -- the fossil head lost one and the launcher added six", d))
	}
	if runs(newC) != runs(oldC) {
		fail = append(fail, fmt.Sprintf("runs of two blank lines: %d in the output against %d in the input", runs(newC), runs(oldC)))
	}
	if i := strings.Index(oldC, z18Head); i >= 0 {
		bodyOld := oldC[i+len(z18Head):]
		if j := strings.Index(newC, "vim_main(int argc, char **argv)\n{\n"); j >= 0 {
			bn := newC[j:]
			k := strings.Index(bn, "{\n") + 2
			if end := len(bn) - len(z18Launch); end >= k && bodyOld != bn[k:end] {
				fail = append(fail, "the demoted function's body is not the bytes main()'s was")
			}
		}
	}
	rows := z6RowRe.FindAllString(newC, -1)
	got, _ := harness.CommandNamesIn([]byte(newC), "zero-vim.c")
	if len(rows) != 98 || len(got) != 98 {
		fail = append(fail, "cmdnames[] is not the 98 rows phase 10 left")
	}
	if i := strings.Index(newC, "static struct vimoption options[]"); i >= 0 {
		j := strings.Index(newC[i:], "\n};")
		if len(z12RowRe.FindAllString(newC[i:i+j], -1)) != 108 {
			fail = append(fail, "options[] is not the 108 rows phase 12 left")
		}
	}
	var dirs []string
	allInc := true
	for _, l := range strings.Split(newC, "\n") {
		if strings.HasPrefix(l, "#") {
			dirs = append(dirs, l)
			if !strings.HasPrefix(l, "#include <") {
				allInc = false
			}
		}
	}
	if len(dirs) != 12 || !allInc {
		fail = append(fail, "the output does not have exactly the twelve `#include` directives phase 16 left -- this phase adds no header, and that is the point of doing the demotion before anything that might")
	}
	if regexp.MustCompile(`\bexit\b`).MatchString(newC) && len(regexp.MustCompile(`(?m)^\s*exit\(`).FindAllString(newC, -1)) != 1 {
		fail = append(fail, "`exit(` is not at exactly one statement -- mch_exit's `exit(r);`, which phase 17 left as the file's only one and which is the NEXT phase's, not this one's")
	}
	if mentions(newC, "_exit") > 0 {
		fail = append(fail, "`_exit` is back, and phase 17 took it to zero")
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	r.say("main() is now `static int vim_main(int argc, char **argv)` with its body unchanged BYTE FOR BYTE, and the last six lines of the file are a launcher whose whole content is `return vim_main(argc, argv);`.  +5 lines and two hunks")
	r.cont("the three words one by one, because a substring grep confuses them: `main` 1 -- the launcher, and the only bare `main` in the file -- `vim_main` 2, its definition and the one call, and `vim_main2` 2, which is upstream's and does not move.  No prototype for vim_main: it is defined above its only call")
	r.cont("and `exit(` is still at exactly one statement, mch_exit's `exit(r);` -- this phase does not touch it, and the twelve #includes are phase 16's")

	// --- 3. the compile, the linkage and the libc surface --------------------
	before := readFile(filepath.Join(state, "symbols", "undefined"))
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	afterTxt := readFile(".cache/symbols/last/undefined")
	if before != afterTxt {
		b, a := strings.Fields(before), strings.Fields(afterTxt)
		r.say("the libc surface moved, and this phase frees nothing and adds nothing:")
		r.cont("  gone: %s ", strings.Join(comm23(b, a), " "))
		r.cont("  came: %s ", strings.Join(comm23(a, b), " "))
		return harness.ErrReported
	}
	after := strings.Fields(afterTxt)
	if !contains(after, "exit") {
		return stop("exit went, and it is the NEXT phase's: this one moves main() and nothing else")
	}
	for _, absent := range strings.Fields("open creat openat stat access fcntl getcwd strerror fopen fdopen opendir fclose getc putc fsync _exit") {
		if contains(after, absent) {
			return stop("%s is undefined, and the core has had no way to open a file since phase 13", absent)
		}
	}
	r.say("symbols %s -> %s, the two sets IDENTICAL as a cmp and not merely the same size -- moving the entry point is not a libc question, and 'exit' is still undefined because mch_exit still calls it",
		strings.TrimSpace(readFile(".cache/symbols/last/before")),
		strings.TrimSpace(readFile(".cache/symbols/last/after")))

	// --- 4. the binary -------------------------------------------------------
	_ = exec.Command("make", "-C", work, "clean").Run()
	if _, err := os.Stat(filepath.Join(work, "zero-vim")); err == nil {
		(&rep{tag: "build", w: w}).say("the clean did not remove zero-vim")
		return harness.ErrReported
	}
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		(&rep{tag: "build", w: w}).say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	bin, _ := filepath.Abs(filepath.Join(work, "zero-vim"))
	old, _ := filepath.Abs(filepath.Join(state, "old"))
	(&rep{tag: "build", w: w}).say("ok, %s -> %d lines, %d bytes against the input's %d -- NOT asserted equal: at -O0 an extra call frame is real code",
		beforeLines, countLines([]byte(readFile(f))), sizeOf(bin), sizeOf(old))
	if e := <-offDone; e != nil {
		return stop("the control build did not compile")
	}
	if fi, e := os.Stat(offBin); e != nil || fi.Mode()&0o111 == 0 {
		return stop("the control build is missing")
	}

	// --- 5. every way the editor can end, on both binaries and the control ---
	return z18Ways(r, old, bin, offBin)
}

// z18Quiet runs to completion with stdin at /dev/null.  /dev/null AND NOT A
// PIPE, and that was a measurement: with a pipe the harness closes, the EOF case
// came back as a twenty-second timeout on four binaries of five and a clean 1 on
// the fifth -- a race in the HARNESS, not the editor.
func z18Quiet(binary string, args []string) string {
	vim, err := harness.Stage(binary)
	if err != nil {
		return "STAGE"
	}
	home, _ := os.MkdirTemp("", "zero18-home-")
	defer os.RemoveAll(home)
	devnull, _ := os.Open(os.DevNull)
	defer devnull.Close()
	c := exec.Command(vim, args...)
	c.Stdin, c.Stdout, c.Stderr, c.Env = devnull, nil, nil, z2Env(home)
	harness.Setsid(c)
	if err := c.Start(); err != nil {
		return "START"
	}
	done := make(chan error, 1)
	go func() { done <- c.Wait() }()
	select {
	case e := <-done:
		if e == nil {
			return "0"
		}
		return fmt.Sprintf("%d", exitCode(e))
	case <-time.After(20 * time.Second):
		c.Process.Kill()
		<-done
		return "TIMEOUT"
	}
}

func z18Signalled(binary string, sig syscall.Signal) string {
	x := z17Session(binary, []syscall.Signal{sig})
	if strings.Contains(string(x.out), "NEVER DREW") {
		return "NEVER DREW"
	}
	return fmt.Sprintf("%d", x.rc)
}

func z18Ways(r *rep, old, bin, off string) error {
	ways := []struct {
		name string
		fn   func(string) string
		want string
		why  string
	}{
		{"quit", func(b string) string { return z18Quiet(b, []string{"+q!"}) }, "0", ":q! -- ex_quit -> getout(0)"},
		{"cquit3", func(b string) string { return z18Quiet(b, []string{"+cq 3"}) }, "3", ":cq 3 -- ex_cquit -> getout(3)"},
		{"eof", func(b string) string { return z18Quiet(b, nil) }, "1", "end of input -- read_error_exit -> preserve_exit -> getout(1)"},
		{"badopt", func(b string) string { return z18Quiet(b, []string{"-Z"}) }, "1", "a bad option -- mainerr -> mch_exit(1)"},
		{"sigterm", func(b string) string { return z18Signalled(b, syscall.SIGTERM) }, "1", "SIGTERM -- deathtrap -> preserve_exit -> getout(1)"},
		{"sighup", func(b string) string { return z18Signalled(b, syscall.SIGHUP) }, "1", "SIGHUP -- deathtrap -> preserve_exit -> getout(1)"},
	}
	got := map[[2]string]string{}
	var mu sync.Mutex
	var wg sync.WaitGroup
	for _, w := range ways {
		for _, bt := range [][2]string{{"old", old}, {"new", bin}, {"off", off}} {
			wg.Add(1)
			go func(name string, fn func(string) string, tag, b string) {
				defer wg.Done()
				v := fn(b)
				mu.Lock()
				got[[2]string{name, tag}] = v
				mu.Unlock()
			}(w.name, w.fn, bt[0], bt[1])
		}
	}
	wg.Wait()
	var fail, rows, offRows []string
	for _, w := range ways {
		o, n, c := got[[2]string{w.name, "old"}], got[[2]string{w.name, "new"}], got[[2]string{w.name, "off"}]
		rows = append(rows, w.name+"="+n)
		offRows = append(offRows, w.name+"="+c)
		if o != w.want {
			fail = append(fail, fmt.Sprintf("the binary this phase was HANDED exited %s on %s, expected %s -- so the agreement below would be two wrong answers agreeing", o, w.why, w.want))
		}
		if n != o {
			fail = append(fail, fmt.Sprintf("%s: the input exited %s and the output %s.  Demoting main() must not move a status -- `return vim_main(argc, argv);` is a value in the path that was not there before", w.why, o, n))
		}
		if c == n {
			fail = append(fail, fmt.Sprintf("the control -- the output with mch_exit's `exit(r)` changed to `exit(r + 1)`, ONE character -- also exited %s on %s, so this row of the table is not measuring anything", c, w.why))
		}
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	r.say("every way the editor can end, the same on both binaries: %s -- ex_quit, ex_cquit, read_error_exit, mainerr and deathtrap twice, which is every route ZERO-PLAN.md maps that a phase can reach from outside", strings.Join(rows, "  "))
	r.cont("and the table is PROVEN able to fail: the output built a second time with mch_exit's `exit(r)` changed to `exit(r + 1)` -- one character -- moves ALL SIX (%s).  Six statuses that agree prove nothing unless a wrong one would have been caught", strings.Join(offRows, "  "))
	return nil
}
