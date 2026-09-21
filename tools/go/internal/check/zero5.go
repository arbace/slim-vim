package check

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero5", Zero5) }

var (
	z5Gone     = []string{"had_minmin", "edit_type", "EDIT_NONE", "EDIT_FILE", "EDIT_STDIN", "ME_TOO_MANY_ARGS", "buflist_add"}
	z5GoneText = []string{"Too many edit arguments", "read_stdin(void)", "read_stdin();"}
	z5Kept     = []string{"MAX_ARG_CMDS", "ME_EXTRA_CMD", "ME_GARBAGE", "ME_UNKNOWN_OPTION",
		"ME_ARG_MISSING", "mainerr_arg_missing", "want_argument", "case 'T':",
		"if (argv[0][0] == '+')", "p_paste"}
	z5MEWant = [][2]string{{"ME_UNKNOWN_OPTION", "0"}, {"ME_ARG_MISSING", "1"},
		{"ME_GARBAGE", "2"}, {"ME_EXTRA_CMD", "3"}}
	z5MERe   = regexp.MustCompile(`(?m)^enum \{ (ME_\w+) = (\d+) \};$`)
	z5RowsRe = regexp.MustCompile(`(?s)(?m)^static char \*\(main_errors\[\]\) =\n\{\n(.*?)^\};\n`)
	z5Unk    = "Unknown option argument"
)

// Zero5 is phase 5's check: argv ends as `+{command}` and `-T {term}`.
//
// FOUR THINGS ARE PROVED HERE and only the first is a grep.  The cut.  The
// RENUMBERING, against DWARF and not against the build, because main_errors[]
// is indexed by the ME_* enumerators and CLAUDE.md's own warning is that a
// build is perfectly happy to renumber a table index wrongly.  The probes, on
// both binaries, because the baselines are one recording of one binary and
// cannot say "the old one opened the file".  And the INSTRUMENT SWAP this phase
// causes: termcheck asks with a file argument, which is an unknown option from
// here on.
func Zero5(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero5 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "noargv", w: w}
	f := filepath.Join(work, "zero-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	src, err := os.ReadFile(f)
	if err != nil {
		return err
	}
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	tmp, err := os.MkdirTemp("", "zero5")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)

	// --- 1. what the cut removed ---------------------------------------------
	for _, g := range z5Gone {
		if n := countWord(src, g); n != 0 {
			return stop("'%s' still has %d mentions", g, n)
		}
	}
	for _, g := range z5GoneText {
		if n := countLinesWith(src, g); n != 0 {
			return stop("'%s' still has %d mentions", g, n)
		}
	}
	// AND WHAT IT DID NOT TOUCH: `read_stdin` as a parameter and `read_cmd_fd`
	// are the stdin phase's, counted so that taking them HERE fails here.
	if n := occurrences(`\bread_stdin\b`, src); n != 23 {
		return stop("read_stdin has %d mentions, expected the 23 that are the parameter the stdin phase owns", n)
	}
	if n := occurrences(`\bread_cmd_fd\b`, src); n != 12 {
		return stop("read_cmd_fd has %d mentions, expected 12: the assignment was argv's, the readers are not", n)
	}
	r.say("0 mentions of all seven; read_stdin's 23 parameter mentions and read_cmd_fd's 12 readers untouched")

	// --- 2. what it deliberately kept ----------------------------------------
	for _, k := range z5Kept {
		if !strings.Contains(string(src), k) {
			return stop("'%s' went, and argv ends as +{command} and -T {term}", k)
		}
	}
	if !hasLinePrefix(src, "exe_commands(") {
		return stop("exe_commands went, and with it every +{command}")
	}
	// The ME_* enumerators are main_errors[]'s indices: 0..3, in table order.
	pairs := z5MERe.FindAllStringSubmatch(string(src), -1)
	got := make([][2]string, len(pairs))
	for i, p := range pairs {
		got[i] = [2]string{p[1], p[2]}
	}
	if !z5PairsEq(got, z5MEWant) {
		return stop("the ME_* enumerators are %s, expected %s", z5PairsRepr(got), z5PairsRepr(z5MEWant))
	}
	rows := z5RowsRe.FindStringSubmatch(string(src))
	if rows == nil {
		return stop("main_errors[] has no rows, expected 5: four the enumerators index and the one whim left unreachable")
	}
	if n := len(strings.Split(strings.TrimRight(rows[1], "\n"), "\n")); n != 5 {
		return stop("main_errors[] has %d rows, expected 5: four the enumerators index and the one whim left unreachable", n)
	}
	if strings.Contains(rows[1], "Too many edit arguments") {
		return stop("main_errors[] still carries the ME_TOO_MANY_ARGS row")
	}
	r.say("kept: +{command} with MAX_ARG_CMDS, -T with want_argument, ME_UNKNOWN_OPTION for the rest, exe_commands, 'paste'")

	// --- 3. the compile, the linkage and the libc surface --------------------
	// NOTHING IS FREED HERE, stated as an equality so that a symbol ARRIVING --
	// which a fold can do -- fails.
	before := readFile(filepath.Join(state, "symbols", "undefined"))
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	after := readFile(".cache/symbols/last/undefined")
	if before != after {
		r.say("the libc surface moved, and this phase frees nothing:")
		for _, l := range diffLines(before, after) {
			r.cont("  %s", l)
		}
		return harness.ErrReported
	}
	r.say("symbols %s, the same set: nothing this cut removed was libc's last caller",
		strings.TrimSpace(readFile(".cache/symbols/last/after")))

	// --- 4. the enumerators, from DWARF --------------------------------------
	enumsAfter := filepath.Join(tmp, "enums-after")
	if err := exec.Command("sh", "tools/enumvals.sh", f, enumsAfter).Run(); err != nil {
		return fmt.Errorf("tools/enumvals.sh refused")
	}
	if err := z5Enums(r, readFile(filepath.Join(state, "enums-before")), readFile(enumsAfter)); err != nil {
		return err
	}

	// --- 5. the binary -------------------------------------------------------
	_ = exec.Command("make", "-C", work, "clean").Run()
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		(&rep{tag: "build", w: w}).say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	bin, _ := filepath.Abs(filepath.Join(work, "zero-vim"))
	old, _ := filepath.Abs(filepath.Join(state, "old"))
	now, _ := os.ReadFile(f)
	(&rep{tag: "build", w: w}).say("ok, %s -> %d lines, %d bytes", beforeLines, countLines(now), sizeOf(bin))

	// --- 6. the probes, both halves ------------------------------------------
	if err := z5Probes(r, old, bin); err != nil {
		return err
	}

	// --- 7. a real terminal --------------------------------------------------
	if err := z5Pty(r, old, bin); err != nil {
		return err
	}

	// --- 8. the instrument this phase broke, and the one that replaced it ----
	base := ".reference/zero-baselines/ref-term.txt"
	termOld := filepath.Join(tmp, "term-old")
	if err := exec.Command("sh", "tools/st.sh", "ztermcheck", old, termOld).Run(); err != nil {
		return fmt.Errorf("ztermcheck refused")
	}
	if readFile(base) != readFile(termOld) {
		r.say("ztermcheck does not record the baseline from the input binary:")
		for i, l := range diffLines(readFile(base), readFile(termOld)) {
			if i >= 5 {
				break
			}
			r.cont("  %s", l)
		}
		return harness.ErrReported
	}
	termFile := filepath.Join(tmp, "term-file")
	_ = exec.Command("sh", "tools/st.sh", "termcheck", bin, termFile).Run()
	if !strings.Contains(readFile(termFile), "(none)") {
		r.say("termcheck still works on this binary -- then the file")
		r.cont("  argument was not removed, and zrecord.sh need not have changed")
		return harness.ErrReported
	}
	r.say("terminal table: ztermcheck records the baseline's %d rows from the input binary; termcheck's file argument now gives %d empty ones",
		countLines([]byte(readFile(base))), countLinesWith([]byte(readFile(termFile)), "(none)"))
	return nil
}

func z5PairsEq(a, b [][2]string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// z5PairsRepr is Python's %r of a list of tuples, because the refusal message
// is compared byte for byte against the shell's.
func z5PairsRepr(p [][2]string) string {
	q := make([]string, len(p))
	for i, v := range p {
		q[i] = fmt.Sprintf("('%s', '%s')", v[0], v[1])
	}
	return "[" + strings.Join(q, ", ") + "]"
}

// z5Enums is the DWARF comparison: 1,327 enumerators, of which four must be
// gone, three must be exactly one lower, and every other must be unmoved.  A
// wrong table index would not show up anywhere else.
func z5Enums(r *rep, beforeTxt, afterTxt string) error {
	load := func(s string) map[string]string {
		m := map[string]string{}
		for _, l := range strings.Split(s, "\n") {
			if i := strings.IndexByte(l, '='); i > 0 {
				m[l[:i]] = strings.TrimRight(l[i+1:], "\n")
			}
		}
		return m
	}
	before, after := load(beforeTxt), load(afterTxt)
	goneSet := map[string]bool{"ME_TOO_MANY_ARGS": true, "EDIT_NONE": true, "EDIT_FILE": true, "EDIT_STDIN": true}
	moved := map[string][2]string{"ME_ARG_MISSING": {"2", "1"}, "ME_GARBAGE": {"3", "2"}, "ME_EXTRA_CMD": {"4", "3"}}
	var fail []string
	gs := make([]string, 0, len(goneSet))
	for n := range goneSet {
		gs = append(gs, n)
	}
	sort.Strings(gs)
	for _, n := range gs {
		if _, ok := before[n]; !ok {
			fail = append(fail, fmt.Sprintf("%s was not in the input binary at all, so its removal proves nothing", n))
		}
		if v, ok := after[n]; ok {
			fail = append(fail, fmt.Sprintf("%s survives with value %s", n, v))
		}
	}
	ms := make([]string, 0, len(moved))
	for n := range moved {
		ms = append(ms, n)
	}
	sort.Strings(ms)
	for _, n := range ms {
		wasNow := moved[n]
		if before[n] != wasNow[0] || after[n] != wasNow[1] {
			fail = append(fail, fmt.Sprintf("%s is %s -> %s, expected %s -> %s",
				n, pyNone(before[n]), pyNone(after[n]), wasNow[0], wasNow[1]))
		}
	}
	var still, movedN, lost []string
	for n := range before {
		if goneSet[n] {
			continue
		}
		if _, ok := moved[n]; ok {
			continue
		}
		still = append(still, n)
		if v, ok := after[n]; ok && v != before[n] {
			movedN = append(movedN, n)
		} else if !ok {
			lost = append(lost, n)
		}
	}
	sort.Strings(movedN)
	sort.Strings(lost)
	if len(movedN) > 0 {
		fail = append(fail, fmt.Sprintf("%d enumerators renumbered and were not to: %s", len(movedN), strings.Join(head8(movedN), " ")))
	}
	if len(lost) > 0 {
		fail = append(fail, fmt.Sprintf("%d enumerators left the binary and were not to: %s", len(lost), strings.Join(head8(lost), " ")))
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		r.cont("main_errors[] is indexed by these, and the build cannot see a")
		r.cont("wrong index.  DWARF can.")
		return harness.ErrReported
	}
	r.say("enumerators: %d in, %d out; 4 gone, 3 renumbered by one, %d unmoved",
		len(before), len(after), len(still)-len(movedN))
	return nil
}

func pyNone(s string) string {
	if s == "" {
		return "None"
	}
	return s
}

func head8(s []string) []string {
	if len(s) > 8 {
		return s[:8]
	}
	return s
}

var _ = sha256.Sum256
var _ = hex.EncodeToString
var _ = sync.WaitGroup{}
var _ = time.Second
var _ = io.Discard
