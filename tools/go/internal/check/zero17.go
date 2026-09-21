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

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero17", Zero17) }

// The instrument's anchors.  Each must occur exactly once or the zero it
// measures is a probe that cannot fail.
const (
	z17Enter = "    ++entered;\n\n    block_autocmds();\n"
	z17Mark  = "    ++entered;\n" +
		"\n" +
		"    {\n" +
		"        char dtbuf[4];\n" +
		"        dtbuf[0] = 'D';\n" +
		"        dtbuf[1] = 'T';\n" +
		"        dtbuf[2] = (char)('0' + (entered > 9 ? 9 : entered));\n" +
		"        dtbuf[3] = '\\n';\n" +
		"        (void)write(2, dtbuf, 4);\n" +
		"    }\n" +
		"\n" +
		"    block_autocmds();\n"
	z17Ladder      = "    if (entered >= 3)\n    {\n        reset_signals();\n"
	z17LadderMark  = "    if (entered >= 3)\n    {\n        (void)write(2, \"DTLADDER\\n\", 9);\n        reset_signals();\n"
	z17Preserve    = "preserve_exit(void)\n{\n\n    prepare_to_exit();\n"
	z17PreserveR   = "preserve_exit(void)\n{\n\n    raise(SIGHUP);\n\n    prepare_to_exit();\n"
	z17Double      = "    if (entered == 2)\n    {\n         out_str((char_u *)(\"Vim: Double signal, exiting\\n\")) ;\n"
	z17DoubleR     = "    if (entered == 2)\n    {\n        raise(SIGTERM);\n         out_str((char_u *)(\"Vim: Double signal, exiting\\n\")) ;\n"
	z17Flags       = "            sa.sa_flags = 0;\n"
	z17FlagsNodef  = "            sa.sa_flags = SA_NODEFER;\n"
	z17BeforeL     = "    full_screen = FALSE;\n    if (entered >= 3)\n"
	z17BeforeLR    = "    full_screen = FALSE;\n    if (entered == 3)\n    {\n        raise(SIGHUP);\n    }\n    if (entered >= 3)\n"
	z17LadderWhole = "    if (entered >= 3)\n    {\n        reset_signals();\n        if (entered >= 4)\n        {\n            _exit(8);\n        }\n        exit(7);\n    }\n"
	z17Table       = "} signal_info[] =\n{\n    {SIGHUP,        \"HUP\",      TRUE},\n    {SIGTERM,       \"TERM\",     TRUE},\n    {SIGINT,        \"INT\",      FALSE},\n    {SIGWINCH,      \"WINCH\",    FALSE},\n    {SIGTSTP,       \"TSTP\",     FALSE},\n    {-1,            \"Unknown!\", FALSE}\n};\n"
	z17Install     = "        if (signal_info[i].deadly)\n        {\n            struct sigaction sa;\n\n            sa.sa_handler = func_deadly;\n            sigemptyset(&sa.sa_mask);\n            sa.sa_flags = 0;\n            sigaction(signal_info[i].sig, &sa, NULL);\n        }\n"
)

var z17Builds = []string{"in_mark", "in_forced", "in_nodefer3", "in_nodefer4", "out_forced"}

// Zero17 is phase 17's check: the deadly ladder that cannot run.
//
// The evidence is the same source built five ways, of which two differ in ONE
// sigaction field: with sa_flags = 0 a forced double signal stops at depth 2 and
// exits 1, and with SA_NODEFER it reaches depth 3, runs the ladder and exits 7 --
// which is exit(7) executing -- and one forced signal further exits 8, which is
// _exit(8).
func Zero17(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero17 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "deadly", w: w}
	f := filepath.Join(work, "zero-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	tmp, err := os.MkdirTemp("", "zero17")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	inst := filepath.Join(tmp, "i")
	os.MkdirAll(inst, 0o755)

	// --- 1. the five instrumented sources ------------------------------------
	oldC := readFile(filepath.Join(state, "old.c"))
	newC := readFile(f)
	edit := func(text, want, repl, what string) (string, error) {
		if n := strings.Count(text, want); n != 1 {
			return "", stop("%s occurs %d times, expected 1 -- the instrument must land where it is meant to, or the zero it measures is a probe that cannot fail", what, n)
		}
		return strings.Replace(text, want, repl, 1), nil
	}
	chain := func(text string, steps ...[3]string) (string, error) {
		var e error
		for _, s := range steps {
			if text, e = edit(text, s[0], s[1], s[2]); e != nil {
				return "", e
			}
		}
		return text, nil
	}
	inMark, e := chain(oldC, [3]string{z17Enter, z17Mark, "the `++entered;` the depth marker follows"},
		[3]string{z17Ladder, z17LadderMark, "the ladder the second marker opens"})
	if e != nil {
		return e
	}
	inForced, e := chain(inMark, [3]string{z17Preserve, z17PreserveR, "preserve_exit()'s head"},
		[3]string{z17Double, z17DoubleR, "the `entered == 2` arm"})
	if e != nil {
		return e
	}
	inNodefer3, e := chain(inForced, [3]string{z17Flags, z17FlagsNodef, "catch_signals()'s `sa_flags = 0`"})
	if e != nil {
		return e
	}
	inNodefer4, e := chain(inNodefer3, [3]string{z17BeforeL, z17BeforeLR, "the statement before the ladder"})
	if e != nil {
		return e
	}
	if strings.Contains(newC, z17Ladder) {
		return stop("the ladder is still in the output")
	}
	outForced, e := chain(newC, [3]string{z17Enter, z17Mark, "the `++entered;` in the OUTPUT"},
		[3]string{z17Preserve, z17PreserveR, "preserve_exit()'s head in the OUTPUT"},
		[3]string{z17Double, z17DoubleR, "the `entered == 2` arm in the OUTPUT"})
	if e != nil {
		return e
	}
	for n, t := range map[string]string{"in_mark": inMark, "in_forced": inForced,
		"in_nodefer3": inNodefer3, "in_nodefer4": inNodefer4, "out_forced": outForced} {
		os.WriteFile(filepath.Join(inst, n+".c"), []byte(t), 0o644)
	}
	r.say("five instrumented sources: the input marked, the input marked and forced, the same with ONE FIELD changed to SA_NODEFER, the same again forced one step further, and the OUTPUT marked and forced identically")
	mk := readFile(filepath.Join(work, "Makefile"))
	flags := append(strings.Fields(z9Flag(mk, "CFLAGS")), strings.Fields(z9Flag(mk, "LDFLAGS"))...)
	var bwg sync.WaitGroup
	for _, n := range z17Builds {
		bwg.Add(1)
		go func(n string) {
			defer bwg.Done()
			a := append(append([]string{}, flags...), "-o", filepath.Join(inst, n), filepath.Join(inst, n+".c"))
			exec.Command("gcc", a...).Run()
		}(n)
	}

	// --- 2. the source, while the five compile -------------------------------
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
	if strings.Count(oldC, z17LadderWhole) != 1 {
		fail = append(fail, "the input did not hold exactly one `entered >= 3` ladder, so this is not the file the phase was written against")
	}
	if strings.Contains(newC, z17LadderWhole) {
		fail = append(fail, "the ladder survives in the output")
	}
	if mentions(oldC, "exit") != 6 || mentions(newC, "exit") != 5 {
		fail = append(fail, fmt.Sprintf("`exit` as a word is %d in the input and %d in the output, expected 6 and 5 -- two string literals, a `goto exit;`, its `exit:` label in vim_regsub_both(), `exit(7)` and `exit(r)`, of which only `exit(7)` goes",
			mentions(oldC, "exit"), mentions(newC, "exit")))
	}
	if mentions(oldC, "_exit") != 1 || mentions(newC, "_exit") != 0 {
		fail = append(fail, fmt.Sprintf("`_exit` is %d in the input and %d in the output, expected 1 and 0", mentions(oldC, "_exit"), mentions(newC, "_exit")))
	}
	callRe := regexp.MustCompile(`(?m)^\s*exit\(`)
	if co, cn := len(callRe.FindAllString(oldC, -1)), len(callRe.FindAllString(newC, -1)); co != 2 || cn != 1 {
		fail = append(fail, fmt.Sprintf("%d statements begin with `exit(` in the input and %d in the output, expected 2 and 1 -- mch_exit's `exit(r);` is the one that is left, and it is a later phase's", co, cn))
	}
	if !strings.Contains(newC, "    exit(r);\n") {
		fail = append(fail, "mch_exit's `exit(r);` went, and it is not this phase's")
	}
	for _, s := range []string{"SIGSEGV", "SIGBUS", "SIGILL", "SIGFPE", "SIGABRT", "SIGQUIT", "SIGTRAP", "SIGSYS"} {
		if mentions(newC, s) > 0 {
			fail = append(fail, fmt.Sprintf("%s is named in the output, and the ladder was unreachable only because SIGHUP and SIGTERM are the ONLY deadly signals", s))
		}
	}
	if strings.Count(newC, z17Table) != 1 {
		fail = append(fail, "signal_info[] is not the five rows this phase was written against, of which EXACTLY TWO are deadly -- a third `TRUE` row would let `entered` reach 3")
	}
	if strings.Count(newC, z17Install) != 1 {
		fail = append(fail, "catch_signals()'s deadly arm is not the `sigemptyset(&sa.sa_mask)` plus `sa.sa_flags = 0` this phase was written against, and that one field is the whole reason a deadly signal cannot interrupt its own handler")
	}
	for _, flag := range []string{"SA_NODEFER", "SA_RESETHAND", "siginterrupt"} {
		if mentions(newC, flag) > 0 {
			fail = append(fail, fmt.Sprintf("%s is named in the output, and it is exactly what would make the ladder reachable", flag))
		}
	}
	if mentions(newC, "deathtrap") != 3 {
		fail = append(fail, fmt.Sprintf("deathtrap has %d mentions, expected 3 -- a prototype, a definition and the one `catch_signals(deathtrap, SIG_ERR)`.  A fourth would be an ordinary call, which no signal mask protects against", mentions(newC, "deathtrap")))
	}
	if mentions(newC, "reset_signals") != 3 {
		fail = append(fail, fmt.Sprintf("reset_signals has %d mentions, expected 3 -- a prototype, its definition and mainerr()'s call.  The ladder held the fourth, and mainerr() is why the function is NOT orphaned by this cut", mentions(newC, "reset_signals")))
	}
	if mentions(newC, "catch_signals") != 4 {
		fail = append(fail, fmt.Sprintf("catch_signals has %d mentions, expected 4", mentions(newC, "catch_signals")))
	}
	for _, p := range []struct {
		name string
		want int
	}{{"getout", 7}, {"preserve_exit", 3}, {"mch_exit", 8}, {"vim_handle_signal", 5}, {"set_signals", 3}} {
		if mentions(newC, p.name) != p.want {
			fail = append(fail, fmt.Sprintf("%s has %d mentions, expected %d -- this phase touches nothing but the nine lines of the ladder", p.name, mentions(newC, p.name), p.want))
		}
	}
	if ln, lo := len(strings.Split(newC, "\n")), len(strings.Split(oldC, "\n")); ln != lo-9 {
		fail = append(fail, fmt.Sprintf("the file lost %d lines, expected 9", lo-ln))
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
	var d []string
	allInc := true
	for _, l := range strings.Split(newC, "\n") {
		if strings.HasPrefix(l, "#") {
			d = append(d, l)
			if !strings.HasPrefix(l, "#include <") {
				allInc = false
			}
		}
	}
	if len(d) != 12 || !allInc {
		fail = append(fail, "the output does not have exactly the twelve `#include` directives phase 16 left")
	}
	if regexp.MustCompile(`\bFILE\b`).MatchString(newC) {
		fail = append(fail, "FILE is named in zero-vim.c, and phase 13 took it to zero")
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	r.say("the nine lines are gone and nothing else is: `_exit` 1 -> 0, `exit` as a word 6 -> 5 with EXACTLY ONE call left -- mch_exit's `exit(r);`, which is a later phase's -- and reset_signals 4 -> 3, still called by mainerr() and so NOT orphaned")
	r.cont("the two facts the unreachability rests on, asserted on the OUTPUT so a later phase cannot quietly falsify them: signal_info[] is five rows with EXACTLY TWO deadly, no SIGSEGV/SIGBUS/SIGILL/SIGFPE anywhere, and catch_signals()'s deadly arm still installs with `sa.sa_flags = 0` and an empty sa_mask, SA_NODEFER named nowhere")
	r.cont("deathtrap at three mentions -- a prototype, a definition and the one installation -- so a signal is the only way in; and cmdnames[] 98, options[] 108, twelve `#include`s, FILE at 0, none of which this phase touches")
	r.cont("the counting trap: `exit` is FIVE mentions in the output and only one is a call -- two string literals and a `goto exit;` with its `exit:` label in vim_regsub_both() are the others -- so `assert exit at 0` fails on a correct phase and `assert 'exit(' at 0` fails on mch_exit(, preserve_exit( and getout(. The assertion that works is nm -u, in section 3")

	// --- 3. the compile, the linkage and the libc surface --------------------
	before := strings.Fields(readFile(filepath.Join(state, "symbols", "undefined")))
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	after := strings.Fields(readFile(".cache/symbols/last/undefined"))
	goneU, cameU := comm23(before, after), comm23(after, before)
	if strings.Join(goneU, " ") != "_exit" || len(cameU) > 0 {
		r.say("the libc surface did not move by exactly _exit:")
		r.cont("  gone: %s ", strings.Join(goneU, " "))
		r.cont("  came: %s ", strings.Join(cameU, " "))
		return harness.ErrReported
	}
	if !contains(after, "exit") {
		return stop("exit went too, and it is not this phase's: mch_exit's exit(r) is the core's one remaining way to end the process, and demoting it is a later phase's")
	}
	for _, absent := range strings.Fields("open creat openat stat access fcntl getcwd strerror fopen fdopen opendir fclose getc putc fsync") {
		if contains(after, absent) {
			return stop("%s is undefined, and the core has had no way to open a file since phase 13", absent)
		}
	}
	r.say("symbols %s -> %s, the gone set is EXACTLY _exit and nothing arrives -- 'exit' is still undefined, being mch_exit's and a later phase's, and the WORD 'exit' is useless as a source assertion because two string literals and a goto label carry it",
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

	// --- 5. the five instrumented binaries -----------------------------------
	bwg.Wait()
	for _, n := range z17Builds {
		if fi, err := os.Stat(filepath.Join(inst, n)); err != nil || fi.Mode()&0o111 == 0 {
			return stop("the instrumented build %s did not compile", n)
		}
	}
	return z17Evidence(r, inst, old, bin)
}
