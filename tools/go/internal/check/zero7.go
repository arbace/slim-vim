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

	"slimvim.local/tools/internal/cutil"
	"slimvim.local/tools/internal/harness"
)

func init() { register("zero7", Zero7) }

var z7GoneWords = []string{"ex_read", "do_bang", "do_shell", "do_filter", "check_secure",
	"prevcmd_is_set", "prevcmd", "CMD_read", "usefilter"}

// z7GoneStrings lose their last speaker.  `"read"` is the command name; the four
// errors were said by the five functions above and by nothing else.
var z7GoneStrings = []string{`"read"`, "E484: Can't open file", "E319: Sorry",
	"E34: No previous command", "E12: Command not allowed"}

// z7Kept is the BARE WORDS, each with the reason it is not this phase's.  A loop
// that wanted zero for any of these would fail on a correct phase.
var z7Kept = map[string]int{
	"secure": 11, "read": 3, "readfile": 5, "read_buffer": 17, "open_buffer": 6,
	"read_edit": 2, "readonly": 4, "shell": 1, "filter": 2, "check_fname": 4,
}

var z7Later = []string{"check_changed", "do_ecmd", "setfname", "otherfile", "fix_fname",
	"b_ffname", "b_fname", "getexline", "exe_commands", "nv_error"}

var z7QRow = regexp.MustCompile(`(?m)^ *\{'Q', nv_error,`)

// Zero7 is phase 7's check: the way to read a file.
func Zero7(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero7 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "noread", w: w}
	f := filepath.Join(work, "zero-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	src, err := os.ReadFile(f)
	if err != nil {
		return err
	}
	newT, oldT := string(src), readFile(filepath.Join(state, "old.c"))
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }

	// --- 1. what the sweep took ----------------------------------------------
	for _, g := range z7GoneWords {
		if n := countWord(src, g); n != 0 {
			return stop("'%s' still has %d mentions", g, n)
		}
	}
	for _, g := range z7GoneStrings {
		if n := countLinesWith(src, g); n != 0 {
			return stop("the string '%s' still has %d mentions", g, n)
		}
	}
	r.say("six functions, the prevcmd static, the usefilter field and five strings at 0 mentions -- all but the field taken by the sweep")

	// --- 2. and everything that must NOT be at zero --------------------------
	var fail []string
	count := func(t, name string) int {
		return len(regexp.MustCompile(`\b` + regexp.QuoteMeta(name) + `\b`).FindAllString(t, -1))
	}
	names := make([]string, 0, len(z7Kept))
	for n := range z7Kept {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, name := range names {
		want := z7Kept[name]
		if k := count(newT, name); k != want {
			why := "something survived that should not have"
			if k < want {
				why = "this phase reached too far"
			}
			fail = append(fail, fmt.Sprintf("%s has %d mentions, expected %d -- %s", name, k, want, why))
		}
	}
	// E32 stays and E484 goes: the two are the whole difference between "no
	// file name was given" and "the file could not be opened", and only the
	// second was ex_read's.
	if strings.Count(newT, "E32: No file name") != 1 {
		fail = append(fail, "E32: No file name went, and it is reachable through check_fname() from do_ecmd(): it is not this phase's")
	}
	if strings.Contains(newT, "E484: Can't open file") {
		fail = append(fail, "E484: Can't open file survives, and ex_read was its last speaker")
	}
	for _, kept := range z7Later {
		if count(newT, kept) == 0 {
			fail = append(fail, fmt.Sprintf("%s went, and it is a later phase's", kept))
		}
	}
	if !z7QRow.MatchString(newT) {
		fail = append(fail, "the 'Q' row is no longer nv_error's, and phase 4 put it there")
	}
	rows := z6RowRe.FindAllString(newT, -1)
	got, _ := harness.CommandNamesIn(src, "zero-vim.c")
	if len(rows) != 104 || len(got) != 104 {
		fail = append(fail, fmt.Sprintf("cmdnames[] has %d rows and names() reads %d; both must be 104", len(rows), len(got)))
	}
	if contains(got, "read") {
		fail = append(fail, ":read is still a command name")
	}
	for _, name := range []string{"redo", "redraw", "registers", "edit", "print", "append"} {
		if !contains(got, name) {
			fail = append(fail, fmt.Sprintf(":%s went, and it is not this phase's", name))
		}
	}
	if !strings.Contains(newT, "static_assert(sizeof(cmdnames) / sizeof(cmdnames[0]) == CMD_SIZE") {
		fail = append(fail, "the static_assert on the row count went, and it is what catches an enumerator removed without its row")
	}
	// The fold, from the other side: nothing assigns or tests a filter flag,
	// and the two functions whose conditions carried it are still there.
	for _, fn := range []string{"do_one_cmd", "expand_filename"} {
		if _, _, ok := cutil.FindDefinition(src, cutil.Blank(src), fn); !ok {
			fail = append(fail, fmt.Sprintf("%s went, and this phase only folded six tests inside it", fn))
		}
	}
	if count(oldT, "usefilter") != 10 || count(oldT, "check_secure") != 3 {
		fail = append(fail, fmt.Sprintf("the input is not the file this phase was written against: usefilter %d (10), check_secure %d (3)",
			count(oldT, "usefilter"), count(oldT, "check_secure")))
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		r.cont(`a "no mention anywhere" check fails on a correct phase here:`)
		r.cont("`secure` is not check_secure, `read` is a libc call and an")
		r.cont("E222 string, and readfile() belongs to a later phase.")
		return harness.ErrReported
	}
	r.say("kept: secure 11, read 3, readfile 5, read_buffer 17, open_buffer 6, check_fname 4 with E32 -- and E484 has no speaker left")
	r.say("table: 104 rows, names() reads 104, static_assert in place, 4 rows above create_cmdidxs's floor of 100")

	// --- 3. the compile, the linkage and the libc surface --------------------
	// NOTHING IS FREED, stated as an EQUALITY: `:read` reached readfile(),
	// which the startup path still uses, and the shell stubs never called a
	// shell.  A symbol going would mean the cut reached into P8's phase; a
	// symbol arriving would mean the sweep left something that now links.
	before := strings.Fields(readFile(filepath.Join(state, "symbols", "undefined")))
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	after := strings.Fields(readFile(".cache/symbols/last/undefined"))
	if strings.Join(before, "\n") != strings.Join(after, "\n") {
		r.say("the libc surface moved, and this phase frees nothing:")
		r.cont("  gone: %s ", strings.Join(comm23(before, after), " "))
		r.cont("  came: %s ", strings.Join(comm23(after, before), " "))
		r.cont("  open, access and read are the byte-reader phase's (ZERO-PLAN.md P8)")
		return harness.ErrReported
	}
	for _, keep := range []string{"open", "read", "close", "stat"} {
		if !contains(after, keep) {
			return stop("%s is gone, and it is the byte-reader phase's", keep)
		}
	}
	r.say("symbols %s -> %s, the same set: this phase removes two commands, not the read path",
		strings.TrimSpace(readFile(".cache/symbols/last/before")),
		strings.TrimSpace(readFile(".cache/symbols/last/after")))

	// --- 4. the binary -------------------------------------------------------
	_ = exec.Command("make", "-C", work, "clean").Run()
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		(&rep{tag: "build", w: w}).say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	bin, _ := filepath.Abs(filepath.Join(work, "zero-vim"))
	old, _ := filepath.Abs(filepath.Join(state, "old"))
	now, _ := os.ReadFile(f)
	(&rep{tag: "build", w: w}).say("ok, %s -> %d lines, %d bytes", beforeLines, countLines(now), sizeOf(bin))

	// --- 5. the probes, on both binaries -------------------------------------
	if err := z7Probes(r, old, bin); err != nil {
		return err
	}
	// --- 6. a real terminal, and a file the runner wrote ---------------------
	return z7Pty(r, old, bin)
}
