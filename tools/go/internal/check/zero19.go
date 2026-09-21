package check

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"syscall"

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero19", Zero19) }

func z19Probe(ind string) string {
	p := ind
	return p + "{\n" +
		p + "    sigset_t hostmask;\n" +
		p + "    sigemptyset(&hostmask);\n" +
		p + "    sigprocmask(SIG_BLOCK, NULL, &hostmask);\n" +
		p + "    (void)write(2, sigismember(&hostmask, SIGTERM) ? \"TERM-MASKED\\n\" : \"TERM-CLEAR\\n\", sigismember(&hostmask, SIGTERM) ? 12 : 11);\n" +
		p + "    (void)write(2, sigismember(&hostmask, SIGHUP) ? \"HUP-MASKED\\n\" : \"HUP-CLEAR\\n\", sigismember(&hostmask, SIGHUP) ? 11 : 10);\n" +
		p + "}\n"
}

const (
	z19Builtin = "static void *host_jump[5];\nstatic int host_code;\n\n    static void\nhost_exit(int r)\n{\n    host_code = r;\n    __builtin_longjmp(host_jump, 1);\n}\n"
	z19Sigjmp  = "static sigjmp_buf host_jump;\nstatic int host_code;\n\n    static void\nhost_exit(int r)\n{\n    host_code = r;\n    siglongjmp(host_jump, 1);\n}\n"
	z19Launch  = "\nstatic void *host_jump[5];\nstatic int host_code;\n\n    static void\nhost_exit(int r)\n{\n    host_code = r;\n    __builtin_longjmp(host_jump, 1);\n}\n\n    int\nmain(int argc, char **argv)\n{\n    if (__builtin_setjmp(host_jump) != 0)\n    {\n        return host_code;\n    }\n    return vim_main(argc, argv, host_exit);\n}\n"
)

// Zero19 is phase 19's check: the core can no longer stop the process.
// mch_exit()'s `exit(r);` becomes `vim_host_exit(r);` through a pointer the
// launcher installs, and the launcher lands on __builtin_setjmp and returns.
func Zero19(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero19 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "hostexit", w: w}
	f := filepath.Join(work, "zero-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	tmp, err := os.MkdirTemp("", "zero19")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	inst := filepath.Join(tmp, "i")
	os.MkdirAll(inst, 0o755)
	oldC, newC := readFile(filepath.Join(state, "old.c")), readFile(f)

	// --- 1. the four other sources -------------------------------------------
	edit := func(text, want, repl, what string) (string, error) {
		if n := strings.Count(text, want); n != 1 {
			return "", stop("%s occurs %d times, expected 1 -- a probe must land where it is meant to, or what it measures is not what it is read as", what, n)
		}
		return strings.Replace(text, want, repl, 1), nil
	}
	inMask, e := edit(oldC, "    exit(r);\n", z19Probe("    ")+"    exit(r);\n", "mch_exit's `exit(r);` in the INPUT")
	if e != nil {
		return e
	}
	outMask, e := edit(newC, "        return host_code;\n", z19Probe("        ")+"        return host_code;\n", "the launcher's `return host_code;` in the OUTPUT")
	if e != nil {
		return e
	}
	alt, e := edit(newC, z19Builtin, z19Sigjmp, "the launcher's jump, in the OUTPUT")
	if e != nil {
		return e
	}
	if alt, e = edit(alt, "    if (__builtin_setjmp(host_jump) != 0)\n", "    if (sigsetjmp(host_jump, 1) != 0)\n", "main()'s landing site"); e != nil {
		return e
	}
	if alt, e = edit(alt, "#include <stdio.h>\n", "#include <stdio.h>\n#include <setjmp.h>\n", "the first #include"); e != nil {
		return e
	}
	off, e := edit(newC, "    host_code = r;\n", "    host_code = r + 1;\n", "host_exit's one assignment")
	if e != nil {
		return e
	}
	for n, t := range map[string]string{"in_mask": inMask, "out_mask": outMask, "alt": alt, "off": off} {
		os.WriteFile(filepath.Join(inst, n+".c"), []byte(t), 0o644)
	}
	r.say("four more sources: the input asked what signals are blocked immediately before `exit(r);`, the output asked the same immediately before `return host_code;`, the output with the launcher rewritten to sigsetjmp/siglongjmp out of <setjmp.h>, and the output with `host_code = r;` made `host_code = r + 1;`")
	mk := readFile(filepath.Join(work, "Makefile"))
	cflags, ldflags := strings.Fields(z9Flag(mk, "CFLAGS")), strings.Fields(z9Flag(mk, "LDFLAGS"))
	var bwg sync.WaitGroup
	for _, n := range []string{"in_mask", "out_mask", "off"} {
		bwg.Add(1)
		go func(n string) {
			defer bwg.Done()
			a := append(append(append([]string{}, cflags...), ldflags...), "-o", filepath.Join(inst, n), filepath.Join(inst, n+".c"))
			exec.Command("gcc", a...).Run()
		}(n)
	}
	bwg.Add(1)
	go func() {
		defer bwg.Done()
		a := append(append([]string{}, cflags...), "-c", "-o", filepath.Join(inst, "alt.o"), filepath.Join(inst, "alt.c"))
		exec.Command("gcc", a...).Run()
	}()

	// --- 2. the source, while those compile ----------------------------------
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
	exitStmt := regexp.MustCompile(`(?m)^\s*exit\(`)
	if strings.Count(oldC, "    exit(r);\n") != 1 || len(exitStmt.FindAllString(oldC, -1)) != 1 {
		fail = append(fail, "the input did not hold exactly one `exit(` statement, so this is not the file the phase was written against -- phase 17 is what left one")
	}
	for _, name := range []string{"vim_host_exit", "host_exit", "host_jump", "host_code"} {
		if mentions(oldC, name) > 0 {
			fail = append(fail, fmt.Sprintf("`%s` was already a word in the input", name))
		}
	}
	if mentions(oldC, "exit") != 5 || mentions(newC, "exit") != 4 {
		fail = append(fail, fmt.Sprintf("`exit` as a word is %d in the input and %d in the output, expected 5 and 4 -- two string literals, a `goto exit;` and its `exit:` label in vim_regsub_both() are the four that stay, and `exit(r);` is the one that goes", mentions(oldC, "exit"), mentions(newC, "exit")))
	}
	if exitStmt.MatchString(newC) {
		fail = append(fail, "a statement in the output still begins with `exit(`")
	}
	if mentions(newC, "_exit") > 0 {
		fail = append(fail, "`_exit` is back, and phase 17 took it to zero")
	}
	for _, name := range []string{"setjmp", "longjmp", "sigsetjmp", "siglongjmp", "sigjmp_buf", "jmp_buf"} {
		if mentions(newC, name) > 0 {
			fail = append(fail, fmt.Sprintf("`%s` is named in the output.  The launcher jumps with gcc's builtins, which emit no call and no relocation; the library spellings cost two undefined symbols and a thirteenth #include, which is worse than not doing this phase", name))
		}
	}
	for _, p := range []struct{ text, what string }{
		{"static void (*vim_host_exit)(int);\n\n    static void\nmch_exit(int r)\n{\n", "the pointer declared immediately above mch_exit(), its one reader"},
		{"    ml_close_all(TRUE);\n\n    vim_host_exit(r);\n}\n", "mch_exit()'s tail: everything it did before is unchanged and only the last statement moved"},
		{"    static int\nvim_main(int argc, char **argv, void (*exit_fn)(int))\n{\n\n    vim_host_exit = exit_fn;\n", "vim_main() taking the callback as a parameter and installing it"},
	} {
		if strings.Count(newC, p.text) != 1 {
			fail = append(fail, fmt.Sprintf("%s: not found exactly once in the output", p.what))
		}
	}
	if !strings.HasSuffix(newC, z19Launch) {
		fail = append(fail, "zero-vim.c does not end with the twenty-line launcher.  CLAUDE.md states that main() is literally the last thing in this file and its closing brace the final line, and that stays true")
	}
	for _, p := range []struct {
		name string
		want int
		why  string
	}{
		{"vim_host_exit", 3, "its declaration, the one call in mch_exit and the one assignment in vim_main"},
		{"host_exit", 2, "the launcher's definition and the argument main() passes.  `vim_host_exit` is a different word"},
		{"host_jump", 3, "its declaration, the longjmp and the setjmp"},
		{"host_code", 3, "its declaration, the write and the return"},
		{"vim_main", 2, "its definition and the one call from the launcher"},
		{"vim_main2", 2, "upstream's, untouched"},
		{"main", 1, "the launcher's head, still the only bare `main` in the file"},
		{"mch_exit", 8, "this phase changes one statement inside it and no call to it"},
		{"getout", 7, "untouched"},
		{"preserve_exit", 3, "untouched"},
		{"deathtrap", 3, "a prototype, a definition and the one installation"},
	} {
		if mentions(newC, p.name) != p.want {
			fail = append(fail, fmt.Sprintf("`%s` as a whole word has %d mentions, expected %d -- %s", p.name, mentions(newC, p.name), p.want, p.why))
		}
	}
	if d := len(strings.Split(newC, "\n")) - len(strings.Split(oldC, "\n")); d != 18 {
		fail = append(fail, fmt.Sprintf("the file gained %d lines, expected 18", d))
	}
	if runs(newC) != runs(oldC) {
		fail = append(fail, fmt.Sprintf("runs of two blank lines: %d in the output against %d in the input", runs(newC), runs(oldC)))
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
	nd, allInc := 0, true
	for _, l := range strings.Split(newC, "\n") {
		if strings.HasPrefix(l, "#") {
			nd++
			if !strings.HasPrefix(l, "#include <") {
				allInc = false
			}
		}
	}
	if nd != 12 || !allInc {
		fail = append(fail, "the output does not have exactly the twelve `#include` directives phase 16 left -- a thirteenth would be <setjmp.h>, and avoiding it is half of why the launcher jumps with gcc builtins")
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	r.say("mch_exit() ends `vim_host_exit(r);`, the pointer is declared above it, vim_main() takes the callback as its third parameter and installs it, and the launcher is twenty lines that land on __builtin_setjmp and RETURN the status.  +18 lines, four hunks")
	r.cont("the counting trap: `exit` as a word is 5 -> 4 and the number of `exit(` STATEMENTS is 1 -> 0.  The four that stay are two string literals and a `goto exit;` with its `exit:` label in vim_regsub_both(), so `assert exit at 0` fails on a correct phase.  No spelling of setjmp or longjmp is in the file either")
	r.cont("and the twelve #includes are phase 16's, untouched: <setjmp.h> would be a thirteenth, which is half of what the library spelling costs")

	// --- 3. the compile, the linkage and the libc surface --------------------
	before := strings.Fields(readFile(filepath.Join(state, "symbols", "undefined")))
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	after := strings.Fields(readFile(".cache/symbols/last/undefined"))
	goneU, cameU := comm23(before, after), comm23(after, before)
	if strings.Join(goneU, " ") != "exit" || len(cameU) > 0 {
		r.say("the libc surface did not move by exactly exit:")
		r.cont("gone: %s", trSpace(goneU))
		r.cont("came: %s", trSpace(cameU))
		r.cont("NOTHING MAY ARRIVE.  An indirect call names no symbol, and a")
		r.cont("jump that named one would trade two symbols for one.")
		return harness.ErrReported
	}
	for _, absent := range strings.Fields("exit _exit setjmp _setjmp sigsetjmp __sigsetjmp longjmp siglongjmp abort _Exit quick_exit atexit") {
		if contains(after, absent) {
			return stop("%s is undefined, and the core has no way to end the process any more", absent)
		}
	}
	for _, absent := range strings.Fields("open creat openat stat access fcntl getcwd strerror fopen fdopen opendir fclose getc putc fsync") {
		if contains(after, absent) {
			return stop("%s is undefined, and the core has had no way to open a file since phase 13", absent)
		}
	}
	r.say("symbols %s -> %s, the gone set is EXACTLY exit and NOTHING arrives -- the core cannot end the process, cannot abort, cannot _exit and names no jump",
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
	(&rep{tag: "build", w: w}).say("ok, %s -> %d lines, %d bytes", beforeLines, countLines([]byte(readFile(f))), sizeOf(bin))

	// --- 5. the road not taken, as a number ----------------------------------
	bwg.Wait()
	altO := filepath.Join(inst, "alt.o")
	if _, err := os.Stat(altO); err != nil {
		return stop("the sigsetjmp variant did not compile")
	}
	nmOut, _ := exec.Command("nm", "-u", altO).Output()
	var altU []string
	for _, l := range strings.Split(strings.TrimSpace(string(nmOut)), "\n") {
		if fs := strings.Fields(l); len(fs) > 0 {
			altU = append(altU, fs[len(fs)-1])
		}
	}
	sort.Strings(altU)
	for _, want := range []string{"sigsetjmp", "siglongjmp"} {
		if !contains(altU, want) {
			return stop("the sigsetjmp variant does not need %s, so it is not the variant this phase is arguing against", want)
		}
	}
	if contains(altU, "exit") {
		return stop("the sigsetjmp variant still needs exit, so it is not comparable")
	}
	nOut := countLines([]byte(readFile(".cache/symbols/last/undefined")))
	if len(altU) <= nOut {
		return stop("the sigsetjmp variant needs %d symbols against the output's %d, and the whole argument for the builtin is that it needs MORE", len(altU), nOut)
	}
	r.say("THE ROAD NOT TAKEN, measured: the same output with the launcher rewritten to sigsetjmp/siglongjmp out of <setjmp.h> needs %d undefined symbols against this one's %d -- exit goes either way, and the library spelling brings sigsetjmp and siglongjmp in its place.  Two symbols for one, plus a thirteenth #include: worse than not doing the phase", len(altU), nOut)
	for _, n := range []string{"in_mask", "out_mask", "off"} {
		if fi, e := os.Stat(filepath.Join(inst, n)); e != nil || fi.Mode()&0o111 == 0 {
			return stop("the %s build is missing", n)
		}
	}
	return z19Ways(r, old, bin, filepath.Join(inst, "off"), filepath.Join(inst, "in_mask"), filepath.Join(inst, "out_mask"))
}

// z19Marks is the sorted set of mask lines one run wrote to stderr.
func z19Marks(err []byte) []string {
	var out []string
	for _, l := range strings.Split(string(err), "\n") {
		switch l {
		case "TERM-MASKED", "TERM-CLEAR", "HUP-MASKED", "HUP-CLEAR":
			out = append(out, l)
		}
	}
	sort.Strings(out)
	return out
}

func z19Ways(r *rep, old, bin, off, inMask, outMask string) error {
	ways := []struct {
		name string
		fn   func(string) string
		want string
		why  string
	}{
		{"quit", func(b string) string { return z18Quiet(b, []string{"+q!"}) }, "0", ":q! -- ex_quit -> getout(0) -> mch_exit(0)"},
		{"cquit3", func(b string) string { return z18Quiet(b, []string{"+cq 3"}) }, "3", ":cq 3 -- ex_cquit -> getout(3)"},
		{"eof", func(b string) string { return z18Quiet(b, nil) }, "1", "end of input -- read_error_exit -> preserve_exit -> getout(1)"},
		{"badopt", func(b string) string { return z18Quiet(b, []string{"-Z"}) }, "1", "a bad option -- mainerr -> mch_exit(1), which never reaches the editor at all"},
		{"sigterm", func(b string) string { return z18Signalled(b, syscall.SIGTERM) }, "1", "SIGTERM -- deathtrap -> preserve_exit -> getout(1), from inside a signal handler"},
		{"sighup", func(b string) string { return z18Signalled(b, syscall.SIGHUP) }, "1", "SIGHUP -- deathtrap -> preserve_exit -> getout(1), from inside a signal handler"},
	}
	got := map[[2]string]string{}
	masks := map[string]z19Rec{}
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
	for _, m := range []struct {
		name, bin string
		sig       syscall.Signal
	}{{"in_term", inMask, syscall.SIGTERM}, {"in_hup", inMask, syscall.SIGHUP},
		{"out_term", outMask, syscall.SIGTERM}, {"out_hup", outMask, syscall.SIGHUP}} {
		wg.Add(1)
		go func(name, b string, s syscall.Signal) {
			defer wg.Done()
			x := z19Signalled(b, s)
			mu.Lock()
			masks[name] = x
			mu.Unlock()
		}(m.name, m.bin, m.sig)
	}
	wg.Wait()
	var fail, rows, offRows, maskRows []string
	for _, w := range ways {
		o, n, c := got[[2]string{w.name, "old"}], got[[2]string{w.name, "new"}], got[[2]string{w.name, "off"}]
		rows = append(rows, w.name+"="+n)
		offRows = append(offRows, w.name+"="+c)
		if o != w.want {
			fail = append(fail, fmt.Sprintf("the binary this phase was HANDED exited %s on %s, expected %s -- so the agreement below would be two wrong answers agreeing", o, w.why, w.want))
		}
		if n != o {
			fail = append(fail, fmt.Sprintf("%s: the input exited %s and the output %s.  The status now travels from mch_exit through a function pointer, into a jump buffer and out of main() as a return value, and every step of that is what this row is checking", w.why, o, n))
		}
		if c == n {
			fail = append(fail, fmt.Sprintf("the control -- the output with host_exit's `host_code = r;` made `host_code = r + 1;`, ONE character -- also exited %s on %s, so this row is not measuring the value travelling", c, w.why))
		}
	}
	for _, sig := range []string{"term", "hup"} {
		a, b := z19Marks(masks["in_"+sig].err), z19Marks(masks["out_"+sig].err)
		up := strings.ToUpper(sig)
		if len(a) == 0 {
			fail = append(fail, fmt.Sprintf("the INPUT instrumented before `exit(r);` reported no mask at all on SIG%s, so the comparison below would be two silences agreeing", up))
		}
		if strings.Join(a, " ") != strings.Join(b, " ") {
			fail = append(fail, fmt.Sprintf("SIG%s: the process used to end with %s and now ends with %s.  __builtin_longjmp does not restore the signal mask, and the whole argument for using it is that exit() was already called from inside the handler with the handled signal blocked",
				up, z19Tuple(a), z19Tuple(b)))
		}
		maskRows = append(maskRows, "SIG"+up+" "+strings.Join(a, " "))
	}
	if masks["in_term"].rc != "1" || masks["out_term"].rc != "1" {
		fail = append(fail, "an instrumented signal run did not exit 1")
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	r.say("every way the editor can end, the same on both binaries: %s -- ex_quit, ex_cquit, read_error_exit, mainerr and deathtrap twice.  Every one of them now leaves mch_exit through a function pointer, lands in main() and comes back as a RETURN VALUE", strings.Join(rows, "  "))
	r.cont("and the table is PROVEN able to fail: the output built again with host_exit's `host_code = r;` made `host_code = r + 1;` -- one character -- moves ALL SIX (%s)", strings.Join(offRows, "  "))
	r.cont("THE SIGNAL MASK THE PROCESS ENDS WITH IS UNCHANGED, which is the one thing sigsetjmp would have bought: %s, identical on the input asked immediately before `exit(r);` and on the output asked immediately before the launcher returns.  exit() was always called from inside the handler with the handled signal blocked -- SIGHUP is clear only because prepare_to_exit() ignores it on the way past -- so __builtin_longjmp PRESERVES that and siglongjmp would CHANGE it", strings.Join(maskRows, ", "))
	return nil
}

func z19Tuple(s []string) string {
	if len(s) == 0 {
		return "nothing"
	}
	q := make([]string, len(s))
	for i, v := range s {
		q[i] = "'" + v + "'"
	}
	if len(q) == 1 {
		return "(" + q[0] + ",)"
	}
	return "(" + strings.Join(q, ", ") + ")"
}

// trSpace is `tr '\n' ' '` of a file holding these lines: every one followed by
// a space, so an empty set is the empty string.
func trSpace(s []string) string {
	var b strings.Builder
	for _, v := range s {
		b.WriteString(v + " ")
	}
	return b.String()
}

type z19Rec struct {
	rc  string
	err []byte
}

// z19Signalled is the heredoc's signalled(): a run that never drew is
// ('NEVER DREW', b''), so its stderr cannot stand in for a mask.
func z19Signalled(binary string, sig syscall.Signal) z19Rec {
	x := z17Session(binary, []syscall.Signal{sig})
	if strings.Contains(string(x.out), "NEVER DREW") {
		return z19Rec{"NEVER DREW", nil}
	}
	return z19Rec{fmt.Sprintf("%d", x.rc), x.err}
}
