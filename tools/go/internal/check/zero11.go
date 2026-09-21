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

	"slimvim.local/tools/internal/cutil"
	"slimvim.local/tools/internal/dead"
	"slimvim.local/tools/internal/harness"
)

func init() { register("zero11", Zero11) }

var z11Gone = []string{"check_changed", "check_changed_any", "no_write_message",
	"no_write_message_nobang", "not_exiting",
	"add_bufnum", "set_curbuf", "enter_buffer", "win_enter", "win_enter_ext",
	"goto_tabpage_win", "goto_tabpage_tp", "get_winopts", "find_wininfo",
	"buflist_findfpos", "buflist_getfpos",
	"w_topline_was_set", "wi_changelistidx", "SHM_FILEINFO"}

var z11GoneStrings = []string{
	"E37: No write since last change (add ! to override)",
	"E37: No write since last change",
	"E162: No write since last change for buffer ",
}

var z11Kept = map[string]int{
	"bufIsChanged": 7, "curbufIsChanged": 7, "bufIsChangedNotTerm": 3,
	"text_locked": 6, "curbuf_locked": 7, "before_quit_autocmds": 2,
	"getout": 7, "mch_exit": 8, "exiting": 13, "buf_spname": 4, "open_buffer": 4,
	"fileinfo": 3, "check_fname": 3, "p_ur": 2, "p_ro": 2, "read_cmd_fd": 12,
	"vim_fsync": 3, "scriptin": 8, "redir_fd": 6, "msg_scrolled_ign": 2,
	"nv_error": 46, "p_wh": 2,
}

var z11EnumWant = []string{"CCGD_ALLBUF", "CCGD_EXCMD", "CCGD_FORCEIT", "CCGD_MULTWIN",
	"DOBUF_GOTO", "DOBUF_UNLOAD", "SHM_FILEINFO",
	"WEE_CURWIN_INVALID", "WEE_TRIGGER_ENTER_AUTOCMDS",
	"WEE_TRIGGER_LEAVE_AUTOCMDS", "WEE_TRIGGER_NEW_AUTOCMDS", "WEE_UNDO_SYNC"}

var (
	z11Decl   = regexp.MustCompile(`(?m)^static\s+[A-Za-z_][\w \t*]*?\b(\w+)\s*(=[^;]*)?;$`)
	z11Assign = regexp.MustCompile(`^\s*(\)\s*)?([-+|&^*/]|<<|>>)?=[^=]`)
)

// Zero11 is phase 11's check: the REFUSAL, `E37: No write since last change`,
// which has had no remedy to offer since phase 6 took every `:write`.
func Zero11(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero11 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "noquit", w: w}
	f := filepath.Join(work, "zero-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	src, err := os.ReadFile(f)
	if err != nil {
		return err
	}
	newT, oldT := string(src), readFile(filepath.Join(state, "old.c"))
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	tmp, err := os.MkdirTemp("", "zero11")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)

	// --- 1. what the sweep took ----------------------------------------------
	for _, g := range z11Gone {
		if n := countWord(src, g); n != 0 {
			return stop("'%s' still has %d mentions", g, n)
		}
	}
	for _, g := range z11GoneStrings {
		if n := countLinesWith(src, g); n != 0 {
			return stop("the string '%s' still has %d mentions", g, n)
		}
	}
	r.say("sixteen functions, two struct fields, SHM_FILEINFO and the three 'No write since last change' literals at 0 mentions -- all of it the sweep's but the two fields, and the edit named not one function")

	// --- 2. what must NOT be at zero -----------------------------------------
	var fail []string
	count := func(t, name string) int {
		return len(regexp.MustCompile(`\b` + regexp.QuoteMeta(name) + `\b`).FindAllString(t, -1))
	}
	nOld := len(dead.FuncDefinitions([]byte(oldT), cutil.Blank([]byte(oldT))))
	nNew := len(dead.FuncDefinitions(src, cutil.Blank(src)))
	if nOld != 1742 || nNew != 1726 {
		fail = append(fail, fmt.Sprintf("the function count went %d -> %d, expected 1742 -> 1726: one fold takes SIXTEEN, and eleven of them are the switch-buffer island", nOld, nNew))
	}
	names := make([]string, 0, len(z11Kept))
	for n := range z11Kept {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, name := range names {
		want := z11Kept[name]
		if k := count(newT, name); k != want {
			why := "something survived that should not have"
			if k < want {
				why = "this phase reached too far"
			}
			fail = append(fail, fmt.Sprintf("%s has %d mentions, expected %d -- %s", name, k, want, why))
		}
	}
	if !regexp.MustCompile(`(?m)^static long\s+p_wh = 1L;$`).MatchString(newT) {
		fail = append(fail, "p_wh lost its initialising declaration, which is the half of its two mentions that makes it look write-only")
	}
	if !regexp.MustCompile(`(?m)^\s*m = p_wh \+ `).MatchString(newT) {
		fail = append(fail, `p_wh lost its one real reader, and a "uses - writes - 1 <= 0" scan would then be right about it for the first time`)
	}
	woOld, woNew := z11WriteOnly(oldT), z11WriteOnly(newT)
	if strings.Join(woNew, " ") != strings.Join(woOld, " ") || strings.Join(woNew, " ") != "vim_ignored" {
		fail = append(fail, fmt.Sprintf("the write-only scan reports %s where the input reports %s; both must be exactly vim_ignored, which is upstream's sink for an ignored return value and was write-only before this phase",
			orNothing(woNew), orNothing(woOld)))
	}
	if strings.Contains(newT, "No write since last change") {
		fail = append(fail, "E37 or E162 survives, and this phase removes the refusal that said them -- phases 6 to 10 all assert the opposite, which is why none of them can share a stage with this one")
	}
	if !strings.Contains(oldT, "No write since last change") {
		fail = append(fail, "the input did not refuse, so this phase is being checked against a file it was not written for")
	}
	for _, lw := range []struct {
		lit  string
		want int
	}{{"[Modified]", 1}, {"[No Name]", 2}, {"E32: No file name", 1}} {
		if k := strings.Count(newT, lw.lit); k != lw.want {
			fail = append(fail, fmt.Sprintf("%s occurs %d times, expected %d -- the buffer still knows it is modified and still has no name; what went is the refusal",
				cutilRepr(lw.lit), k, lw.want))
		}
	}
	body := ""
	if a, z, ok := cutil.FindDefinition(src, cutil.Blank(src), "ex_quit"); ok {
		body = newT[a:z]
	}
	if body == "" {
		fail = append(fail, "ex_quit is gone, and this phase folds it rather than removing it")
	}
	if strings.Contains(body, "save_exiting") || strings.Contains(body, "exiting = TRUE") {
		fail = append(fail, "ex_quit still saves and sets `exiting`: getout() does both itself and never returns, which is why extra B is honest")
	}
	if strings.Count(body, "getout(0);") != 1 {
		fail = append(fail, fmt.Sprintf("ex_quit does not end in exactly one getout(0);: %s", cutilRepr(tailN(body, 120))))
	}
	for _, kept := range []string{"text_locked", "curbuf_locked", "before_quit_autocmds"} {
		if !strings.Contains(body, kept) {
			fail = append(fail, fmt.Sprintf("ex_quit no longer calls %s, and all three early returns are above the anchor and not this phase's", kept))
		}
	}
	zet := ""
	if a, z, ok := cutil.FindDefinition(src, cutil.Blank(src), "nv_Zet"); ok {
		zet = newT[a:z]
	}
	if strings.Count(zet, `do_cmdline_cmd((char_u *)"q!")`) != 2 {
		fail = append(fail, "nv_Zet does not run `q!` for both ZZ and ZQ: it has since phase 6 and rewriting either string would move a record phase 6 declared")
	}
	rows := z6RowRe.FindAllString(newT, -1)
	got, errN := harness.CommandNamesIn(src, "zero-vim.c")
	if errN != nil {
		fail = append(fail, fmt.Sprintf("the checked parser refuses this table -- the row floor is no longer below 98: %s", errN))
	}
	if len(rows) != 98 || len(got) != 98 {
		fail = append(fail, fmt.Sprintf("cmdnames[] has %d rows and names() reads %d; both must be 98 -- this phase removes no command", len(rows), len(got)))
	}
	for _, name := range []string{"quit", "cquit", "registers", "redo", "print"} {
		if !contains(got, name) {
			fail = append(fail, fmt.Sprintf(":%s went, and this phase removes no row at all", name))
		}
	}
	if !strings.Contains(newT, "static_assert(sizeof(cmdnames) / sizeof(cmdnames[0]) == CMD_SIZE") {
		fail = append(fail, "the static_assert on the row count went, and it is what catches an enumerator removed without its row")
	}
	if !z7QRow.MatchString(newT) {
		fail = append(fail, "the 'Q' row is no longer nv_error's, and phase 4 put it there")
	}
	for _, p := range []struct{ opt, v string }{{"'undoreload'", "p_ur"}, {"'readonly'", "p_ro"}} {
		if !strings.Contains(newT, "(char_u *)&"+p.v+",") {
			fail = append(fail, fmt.Sprintf("%s lost its option row, and that is the options phase's: a row removed here would change what :set answers", p.opt))
		}
	}
	// What the sixteen cost the old file, as a difference rather than a number.
	for _, p := range []struct {
		name string
		want int
	}{{"check_changed", 4}, {"check_changed_any", 2}, {"not_exiting", 4},
		{"bufIsChanged", 10}, {"open_buffer", 5}, {"buf_spname", 5},
		{"exiting", 17}, {"p_wh", 4}, {"SHM_FILEINFO", 2}} {
		if count(oldT, p.name) != p.want {
			fail = append(fail, fmt.Sprintf("the input is not the file this phase was written against: %s %d, expected %d",
				p.name, count(oldT, p.name), p.want))
		}
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	r.say("the count is the assertion: 1,742 definitions -> 1,726, ELEVEN of the sixteen being the switch-buffer/switch-window island that hung off check_changed_any()'s tail and that no plan predicted")
	r.cont("kept: bufIsChanged 7 and curbufIsChanged 7 -- the buffer still knows it is modified, so [Modified], [+] and `:set modified?` are untouched -- text_locked 6, curbuf_locked 7 and before_quit_autocmds 2, all three still able to decline above the anchor")
	r.cont("p_wh 4 -> 2 and it is NOT write-only, which is what the obvious scan gets wrong: over every file-scope static, excluding the declaration by position, the only write-only one is vim_ignored -- upstream's sink for an ignored return value, and the same answer on the input")
	r.cont("the later phases' line: p_ro 2 and p_ur 2 with their rows (the options phase's), read_cmd_fd 12 (the terminal's), scriptin 8, redir_fd 6 and vim_fsync 3 (the FILE* phase's)")
	r.cont("table: 98 rows untouched, names() reads 98, static_assert in place, and nv_Zet still runs `q!` for ZZ and for ZQ")

	// --- 3. the compile, the linkage and the libc surface --------------------
	before := strings.Fields(readFile(filepath.Join(state, "symbols", "undefined")))
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	after := strings.Fields(readFile(".cache/symbols/last/undefined"))
	if strings.Join(before, "\n") != strings.Join(after, "\n") {
		r.say("the libc surface moved, and this phase frees nothing:")
		r.cont("  gone: %s ", strings.Join(comm23(before, after), " "))
		r.cont("  came: %s ", strings.Join(comm23(after, before), " "))
		return harness.ErrReported
	}
	for _, keep := range []string{"fclose", "getc", "putc", "fsync", "read", "write", "close", "dup"} {
		if !contains(after, keep) {
			return stop("%s went, and it is not this phase's: fclose, getc, putc and fsync are the FILE* phase's and read, write, close and dup are the terminal's", keep)
		}
	}
	for _, absent := range []string{"open", "access", "fcntl", "stat", "getcwd", "strerror",
		"chmod", "fchmod", "fstat", "lstat", "unlink"} {
		if contains(after, absent) {
			return stop("%s is undefined again, and nothing here may add one", absent)
		}
	}
	r.say("symbols %s -> %s, the same set as a cmp -- sixteen functions go and not one was libc's last caller; fclose, getc, putc and fsync are still there and are the FILE* phase's",
		strings.TrimSpace(readFile(".cache/symbols/last/before")),
		strings.TrimSpace(readFile(".cache/symbols/last/after")))

	// --- 4. the enumerators --------------------------------------------------
	evOld, evNew := filepath.Join(tmp, "ev.old"), filepath.Join(tmp, "ev.new")
	var ewg sync.WaitGroup
	ewg.Add(1)
	go func() { defer ewg.Done(); exec.Command("sh", "tools/enumvals.sh", filepath.Join(state, "old.c"), evOld).Run() }()
	exec.Command("sh", "tools/enumvals.sh", f, evNew).Run()
	ewg.Wait()
	if err := z11Enums(r, readFile(evOld), readFile(evNew)); err != nil {
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

	if err := z11Probes(r, old, bin); err != nil {
		return err
	}
	return z11Pty(r, old, bin)
}

// z11WriteOnly is the scan that must report EXACTLY vim_ignored on both files:
// a static with writes and no reads.  It is here rather than in util.go because
// only this phase asks it, and what it is for is that the phase leaves none.
func z11WriteOnly(text string) []string {
	var out []string
	for _, m := range z11Decl.FindAllStringSubmatchIndex(text, -1) {
		name := text[m[2]:m[3]]
		reads, writes := 0, 0
		for _, x := range regexp.MustCompile(`\b`+regexp.QuoteMeta(name)+`\b`).FindAllStringIndex(text, -1) {
			if x[0] >= m[0] && x[0] < m[1] {
				continue
			}
			end := x[1]
			if z11Assign.MatchString(text[end:min(end+4, len(text))]) {
				writes++
			} else {
				reads++
			}
		}
		if writes > 0 && reads == 0 {
			out = append(out, name)
		}
	}
	sort.Strings(out)
	return out
}

func orNothing(s []string) string {
	if len(s) == 0 {
		return "nothing"
	}
	return strings.Join(s, " ")
}

func tailN(s string, n int) string {
	if len(s) > n {
		return s[len(s)-n:]
	}
	return s
}

func z11Enums(r *rep, oldTxt, newTxt string) error {
	load := func(s string) map[string]string {
		m := map[string]string{}
		for _, l := range strings.Split(s, "\n") {
			if i := strings.LastIndexByte(l, '='); i > 0 {
				m[l[:i]] = l[i+1:]
			}
		}
		return m
	}
	o, n := load(oldTxt), load(newTxt)
	var gone, came, moved []string
	for k := range o {
		if _, ok := n[k]; !ok {
			gone = append(gone, k)
		} else if n[k] != o[k] {
			moved = append(moved, k)
		}
	}
	for k := range n {
		if _, ok := o[k]; !ok {
			came = append(came, k)
		}
	}
	sort.Strings(gone)
	sort.Strings(came)
	sort.Strings(moved)
	if strings.Join(gone, " ") != strings.Join(z11EnumWant, " ") || len(came) > 0 || len(moved) > 0 {
		if strings.Join(gone, " ") != strings.Join(z11EnumWant, " ") {
			r.say("the enumerators that went are %s, expected exactly %s", strings.Join(gone, " "), strings.Join(z11EnumWant, " "))
		}
		if len(came) > 0 {
			r.say("enumerators arrived: %s", strings.Join(came, " "))
		}
		if len(moved) > 0 {
			r.say("survivors renumbered, and no phase that takes whole anonymous definitions may: %s", strings.Join(moved, " "))
		}
		return harness.ErrReported
	}
	r.say("enumerators %d -> %d: the four CCGD_, the two DOBUF_, SHM_FILEINFO and the five WEE_ go as whole anonymous definitions, NOT ONE SURVIVOR RENUMBERED and none arrived -- the opposite of phase 10, where 85 moved",
		len(o), len(n))
	return nil
}

var _ = io.Discard
