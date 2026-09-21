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

func init() { register("zero6", Zero6) }

var z6GoneFuncs = []string{
	"ex_write", "ex_update", "ex_exit", "do_write", "check_writable", "check_overwrite",
	"not_writing", "check_file_readonly", "buf_write", "buf_write_bytes", "check_mtime",
	"time_differs", "write_eintr", "vim_fexists", "mch_setperm", "mch_fsetperm",
	"mch_nodetype", "u_update_save_nr",
}

var z6GoneEnums = []string{"CMD_write", "CMD_wq", "CMD_xit", "CMD_exit", "CMD_update", "CMD_saveas"}

// z6GoneNames are the command NAMES as strings.  `"write"` is NOT among them:
// it is the 'write' option's name and it stays.
var z6GoneNames = []string{`"wq"`, `"xit"`, `"exit"`, `"update"`, `"saveas"`}

var z6Later = []string{"check_changed", "no_write_message", "do_bang", "check_fname",
	"setfname", "otherfile", "fix_fname", "readfile", "b_ffname"}

var z6RowRe = regexp.MustCompile(`(?m)^    \[CMD_\w+\] = \{.*$`)

// Zero6 is phase 6's check: every way to write a file.
//
// THE CORPUS CANNOT SEE WRITING, which is why the probes exist.  Every one of
// zcases's 102 cases types its own text and never names a file, so `cmd_write`
// types `:write` with no file name and the baseline records `E32: No file name`
// -- an editor that FAILED to write.  A declared delta of "cmd_write and zz_key
// moved" is therefore consistent with a phase that changed one error message
// and left buf_write() reachable.
func Zero6(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero6 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "nowrite", w: w}
	f := filepath.Join(work, "zero-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	src, err := os.ReadFile(f)
	if err != nil {
		return err
	}
	newT := string(src)
	oldT := readFile(filepath.Join(state, "old.c"))
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	tmp, err := os.MkdirTemp("", "zero6")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)

	// --- 1. what the sweep took ----------------------------------------------
	for _, g := range append(append([]string{}, z6GoneFuncs...), z6GoneEnums...) {
		if n := countWord(src, g); n != 0 {
			return stop("'%s' still has %d mentions", g, n)
		}
	}
	for _, g := range z6GoneNames {
		if n := countLinesWith(src, g); n != 0 {
			return stop("the string %s still has %d mentions", g, n)
		}
	}
	if hasLinePrefix(src, "check_readonly(") {
		return stop("check_readonly() is still defined")
	}
	r.say("18 functions and the six enumerators at 0 mentions, all taken by the sweep")

	// --- 2. and the two things that must NOT be at zero ----------------------
	var fail []string
	count := func(t, name string) int {
		return len(regexp.MustCompile(`\b` + regexp.QuoteMeta(name) + `\b`).FindAllString(t, -1))
	}
	// check_readonly: the function is gone and the LOCAL in readfile() is not.
	if n := count(newT, "check_readonly"); n != 4 {
		fail = append(fail, fmt.Sprintf("check_readonly has %d mentions, expected the 4 that are readfile()'s local and its uses", n))
	} else {
		a, z, ok := cutil.FindDefinition(src, cutil.Blank(src), "readfile")
		if !ok {
			fail = append(fail, "readfile() is not defined, and it is not this phase's to take")
		} else {
			outside := 0
			for _, m := range regexp.MustCompile(`\bcheck_readonly\b`).FindAllStringIndex(newT, -1) {
				if m[0] < a || m[0] >= z {
					outside++
				}
			}
			if outside > 0 {
				fail = append(fail, fmt.Sprintf("%d mentions of check_readonly are outside readfile()", outside))
			}
		}
	}
	for _, lw := range []struct {
		lit  string
		want int
	}{{`"write"`, 1}, {"E32: No file name", 1}} {
		if k := strings.Count(newT, lw.lit); k != lw.want {
			fail = append(fail, fmt.Sprintf("%s occurs %d times and must occur %d: it is not this phase's",
				cutil.PyRepr(lw.lit), k, lw.want))
		}
	}
	for _, opt := range []string{"p_fs", "p_write", "p_wa"} {
		if k := count(newT, opt); k != 2 {
			fail = append(fail, fmt.Sprintf("%s has %d mentions, expected 2 -- its definition and its option row, which are the options phase's to take", opt, k))
		}
	}
	if count(newT, "append") != 1 || !strings.Contains(newT, "[CMD_append]") {
		fail = append(fail, fmt.Sprintf("exarg_T.append is not the only `append` left (%d), or the :append row went", count(newT, "append")))
	}
	for _, kept := range z6Later {
		if count(newT, kept) == 0 {
			fail = append(fail, fmt.Sprintf("%s went, and it is a later phase's", kept))
		}
	}
	rows := z6RowRe.FindAllString(newT, -1)
	got, _ := harness.CommandNamesIn(src, "zero-vim.c")
	if len(rows) != 105 || len(got) != 105 {
		fail = append(fail, fmt.Sprintf("cmdnames[] has %d rows and names() reads %d; both must be 105", len(rows), len(got)))
	}
	for _, name := range []string{"write", "wq", "xit", "exit", "update", "saveas"} {
		if contains(got, name) {
			fail = append(fail, fmt.Sprintf(":%s is still a command name", name))
		}
	}
	if !strings.Contains(newT, "static_assert(sizeof(cmdnames) / sizeof(cmdnames[0]) == CMD_SIZE") {
		fail = append(fail, "the static_assert on the row count went, and it is what catches an enumerator removed without its row")
	}
	// The libc the write side reached, counted in OCCURRENCES: stat( appears
	// more than once on a line.
	nOld := len(regexp.MustCompile(`\bstat\(`).FindAllString(oldT, -1))
	nNew := len(regexp.MustCompile(`\bstat\(`).FindAllString(newT, -1))
	if nOld != 14 || nNew != 8 {
		fail = append(fail, fmt.Sprintf("stat( is called %d times and was %d; expected 14 -> 8", nNew, nOld))
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		r.cont(`a "no mention anywhere" check fails on a correct phase here:`)
		r.cont(`check_readonly is a local in readfile(), and "write" is an`)
		r.cont("option name.  Both are measured, not assumed.")
		return harness.ErrReported
	}
	r.say(`kept: check_readonly as readfile()'s local (4 mentions), "write" as the option's name, E32 through check_fname, p_fs/p_write/p_wa at their rows`)
	r.say("table: 105 rows, names() reads 105, static_assert in place, 5 rows above create_cmdidxs's floor of 100")
	r.say("stat( 14 -> 8 calls")

	// --- 3. the compile, the linkage and the libc surface --------------------
	// SIX SYMBOLS GO, stated as a SET and not a count: this is the first zero
	// phase that frees any.  The five a later phase owns must still be
	// undefined, so a cut reaching past this boundary fails here.
	before := strings.Fields(readFile(filepath.Join(state, "symbols", "undefined")))
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	after := strings.Fields(readFile(".cache/symbols/last/undefined"))
	goneSet := comm23(before, after)
	came := comm23(after, before)
	want := []string{"chmod", "fchmod", "fstat", "ftruncate", "lstat", "unlink"}
	sort.Strings(want)
	if strings.Join(goneSet, "\n") != strings.Join(want, "\n") || len(came) > 0 {
		r.say("the libc surface is not what this phase frees:")
		r.cont("  gone: %s ", strings.Join(goneSet, " "))
		r.cont("  came: %s ", strings.Join(came, " "))
		r.cont("  expected exactly: chmod fchmod fstat ftruncate lstat unlink")
		return harness.ErrReported
	}
	for _, keep := range []string{"stat", "open", "access", "fsync", "getcwd"} {
		if !contains(after, keep) {
			return stop("%s is gone, and it is a later phase's: stat and getcwd go with the buffer's name, open and access with readfile, fsync with the options", keep)
		}
	}
	r.say("symbols %s -> %s: exactly chmod fchmod fstat ftruncate lstat unlink, and stat/open/access/fsync/getcwd still needed",
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

	// --- 5. the probes, in a directory they keep -----------------------------
	if err := z6Probes(r, old, bin); err != nil {
		return err
	}
	// --- 6. a real terminal --------------------------------------------------
	return z6Pty(r, old, bin)
}
