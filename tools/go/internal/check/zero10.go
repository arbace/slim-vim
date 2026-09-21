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
	"slimvim.local/tools/internal/harness"
)

func init() { register("zero10", Zero10) }

var z10Gone = []string{"ex_file", "rename_buffer", "setfname", "buf_name_changed", "ml_timestamp",
	"ml_upd_block0", "ml_check_b0_id", "buflist_name_nr", "buflist_findlnum",
	"buflist_findname_stat", "buf_setino", "buf_same_ino", "buf_store_time",
	"otherfile_buf", "fname_expand", "fix_fname", "shorten_fname", "shorten_fname1",
	"shorten_buf_fname", "mch_dirname", "mch_FullName", "vim_FullName", "FullName_save",
	"home_replace_save", "expand_filename", "eval_vars", "find_cmdline_var",
	"expand_wildcards", "expand_wildcards_eval", "gen_expand_wildcards",
	"ExpandOne", "ExpandOne_start", "ExpandFromContext", "ExpandEscape",
	"find_file_in_path", "mch_getperm", "mch_isFullName", "mch_has_wildcard",
	"path_with_url", "backslash_halve", "repl_cmdline", "escape_fname", "wildescape",
	"vim_fnamecmp", "vim_fnamencmp", "vim_strsave_fnameescape", "tilde_replace",
	"expand_env_save", "expand_env_save_opt", "expand_files_and_dirs",
	"map_wildopts_to_ewflags", "save_patterns", "vim_strrchr", "vim_findfile_cleanup",
	"vim_findfile_free_visited", "vim_findfile_free_visited_list",
	"ff_clear", "ff_pop", "ff_free_stack_element", "ff_free_visited_list",
	"b_ffname", "b_sfname", "b_fname", "b_dev", "b_ino", "b_dev_valid", "b_mtime", "b_mtime_ns",
	"b_mtime_read", "b_mtime_read_ns", "b_orig_size", "b_orig_mode",
	"CMD_file", "EX_XFILE", "readonlymode"}

var z10GoneStrings = []string{`"file"`, `E447: Can't find file `, "E480: No match",
	"E95: Buffer with this name already exists", "E304: ml_upd_block0",
	"E194: No alternate file name to substitute", "E499: Empty file name",
	`"cword>"`, `"afile>"`, `"sfile>"`, `\n  c  \"%   `, `\n  c  \"#   `}

var z10Kept = map[string]int{
	"buf_spname": 5, "buf_get_fname": 3, "get_trans_bufname": 4, "fileinfo": 3,
	"check_fname": 3, "check_changed": 4, "no_write_message": 3,
	"p_ur": 2, "p_ro": 2, "read_cmd_fd": 12, "vim_fsync": 3,
	"scriptin": 8, "redir_fd": 6, "msg_scrolled_ign": 2, "home_replace": 3,
	"file_name_at_cursor": 3, "find_file_name_in_path": 3,
	"BF_NOTEDITED": 3, "BF_NEW": 3, "b_shortname": 2, "nv_error": 46, "open_buffer": 5,
}

// z10Families and z10Prefix are every enumerator family that goes, and what took
// it: CMD_file is the row, EX_XFILE the flag no row carries any more, and the
// rest are whole anonymous enums typereach takes with the code that named them.
var z10Families = []string{"CMD_file", "EX_XFILE", "B0_FNAME_SIZE_CRYPT", "UB_FNAME"}
var z10Prefix = []string{"EW_", "WILD_", "EXPAND_", "XP_BS_", "SPEC_", "BLOCK0_", "BLN_",
	"ESTACK_", "VSE_", "VALID_"}

var z10Spellings = []string{"f", "fi", "fil", "file", "file!"}

// Zero10 is phase 10's check: the buffer's NAME.
func Zero10(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero10 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "noname", w: w}
	f := filepath.Join(work, "zero-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	src, err := os.ReadFile(f)
	if err != nil {
		return err
	}
	newT, oldT := string(src), readFile(filepath.Join(state, "old.c"))
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	tmp, err := os.MkdirTemp("", "zero10")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)

	// --- 1. what the sweep took ----------------------------------------------
	for _, g := range z10Gone {
		if n := countWord(src, g); n != 0 {
			return stop("'%s' still has %d mentions", g, n)
		}
	}
	for _, g := range z10GoneStrings {
		if n := countLinesWith(src, g); n != 0 {
			return stop("the string '%s' still has %d mentions", g, n)
		}
	}
	r.say("sixty functions, twelve buf_T fields, CMD_file, EX_XFILE, readonlymode and 43 string literals at 0 mentions -- all of it the sweep's but readonlymode, and the edit named not one function")

	// --- 2. and everything that must NOT be at zero --------------------------
	var fail []string
	count := func(t, name string) int {
		return len(regexp.MustCompile(`\b` + regexp.QuoteMeta(name) + `\b`).FindAllString(t, -1))
	}
	names := make([]string, 0, len(z10Kept))
	for n := range z10Kept {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, name := range names {
		want := z10Kept[name]
		if k := count(newT, name); k != want {
			why := "something survived that should not have"
			if k < want {
				why = "this phase reached too far"
			}
			fail = append(fail, fmt.Sprintf("%s has %d mentions, expected %d -- %s", name, k, want, why))
		}
	}
	// THREE FLAGS THAT CAN NEVER BE SET AND ARE STILL READ, named rather than
	// folded.  setfname() was BF_NOTEDITED's only writer and BF_NEW never had
	// one in this tree; fileinfo() still tests both, so CTRL-G asks two
	// questions whose answer is fixed.
	for _, p := range []struct{ flag, fn string }{{"BF_NOTEDITED", "fileinfo"}, {"BF_NEW", "fileinfo"}} {
		a, z, ok := cutil.FindDefinition(src, cutil.Blank(src), p.fn)
		if !ok || !strings.Contains(newT[a:z], p.flag) {
			fail = append(fail, fmt.Sprintf("%s is no longer read by %s, and this phase removes its writer and not its reader", p.flag, p.fn))
		}
		if regexp.MustCompile(`\|=\s*`+p.flag+`\b`).MatchString(newT) || regexp.MustCompile(`\bb_flags = `+p.flag).MatchString(newT) {
			fail = append(fail, fmt.Sprintf("%s is set somewhere, and setfname() was its only writer", p.flag))
		}
	}
	if k := len(regexp.MustCompile(`\bb_shortname\b\s*=[^=]`).FindAllString(newT, -1)); k != 1 {
		fail = append(fail, fmt.Sprintf("b_shortname is assigned %d times; it was already write-only before this phase, with one write", k))
	}
	if k := strings.Count(newT, `"[No Name]"`); k != 2 {
		fail = append(fail, fmt.Sprintf(`"[No Name]" occurs %d times, expected 2 -- buf_get_fname's, which is now the only name a buffer has, and can_unload_buffer's`, k))
	}
	if strings.Count(newT, "E32: No file name") != 1 {
		fail = append(fail, "E32: No file name went, and check_fname() still says it for the `%` register")
	}
	if !strings.Contains(newT, "E37: No write since last change") {
		fail = append(fail, "E37 went, and check_changed() is the :q phase's")
	}
	if strings.Count(newT, "E23: No alternate file") != 1 {
		fail = append(fail, "E23 went, and getaltfname() says it unconditionally now")
	}
	if strings.Contains(newT, "E447") {
		fail = append(fail, "E447 survives, and part G removed the only arm that could say it -- phase 8's check asserts the opposite, which is why the two phases cannot share a stage")
	}
	if !strings.Contains(oldT, "E447") {
		fail = append(fail, "the input did not say E447, so this phase is being checked against a file it was not written for")
	}
	if a, z, ok := cutil.FindDefinition(src, cutil.Blank(src), "check_fname"); ok {
		body := newT[a:z]
		if strings.Contains(body, "if (") || strings.Contains(body, "return OK") {
			fail = append(fail, "check_fname still tests something: `b_ffname == NULL` was TRUE for ever and the fold leaves an unconditional E32")
		}
	}
	rows := z6RowRe.FindAllString(newT, -1)
	got, errN := harness.CommandNamesIn(src, "zero-vim.c")
	if errN != nil {
		fail = append(fail, fmt.Sprintf("the checked parser refuses this table -- the row floor is no longer below 98: %s", errN))
	}
	if len(rows) != 98 || len(got) != 98 {
		fail = append(fail, fmt.Sprintf("cmdnames[] has %d rows and names() reads %d; both must be 98", len(rows), len(got)))
	}
	if len(z6RowRe.FindAllString(oldT, -1)) != 99 {
		fail = append(fail, "the input does not have 99 rows, so this is not the file this phase was written against")
	}
	if contains(got, "file") {
		fail = append(fail, ":file is still a command name")
	}
	for _, name := range []string{"filter", "fixdel", "quit", "print", "append", "registers"} {
		if !contains(got, name) {
			fail = append(fail, fmt.Sprintf(":%s went, and it is not this phase's", name))
		}
	}
	if !strings.Contains(newT, "static_assert(sizeof(cmdnames) / sizeof(cmdnames[0]) == CMD_SIZE") {
		fail = append(fail, "the static_assert on the row count went, and it is what catches an enumerator removed without its row")
	}
	if !z7QRow.MatchString(newT) {
		fail = append(fail, "the 'Q' row is no longer nv_error's, and phase 4 put it there")
	}
	// THE EXEMPTION PHASE 8 KEPT, from the other side.
	m := z8Lock.FindString(newT)
	if m == "" {
		fail = append(fail, "do_one_cmd's curbuf_locked() test went, and this phase removed one conjunct of it and not the test")
	} else if strings.Contains(m, "CMD_") {
		fail = append(fail, fmt.Sprintf("the curbuf_locked() exemption still names a command: %s", cutilRepr(strings.TrimSpace(m))))
	}
	for _, p := range []struct{ opt, v string }{{"'undoreload'", "p_ur"}, {"'readonly'", "p_ro"}} {
		if !strings.Contains(newT, "(char_u *)&"+p.v+",") {
			fail = append(fail, fmt.Sprintf("%s lost its option row, and that is the options phase's: a row removed here would change what :set answers", p.opt))
		}
	}
	for _, p := range []struct {
		name string
		want int
	}{{"b_ffname", 32}, {"b_sfname", 26}, {"b_fname", 29}, {"setfname", 2},
		{"eval_vars", 4}, {"mch_dirname", 5}, {"CMD_file", 4}, {"EX_XFILE", 4}, {"readonlymode", 3}} {
		if count(oldT, p.name) != p.want {
			fail = append(fail, fmt.Sprintf("the input is not the file this phase was written against: %s %d, expected %d",
				p.name, count(oldT, p.name), p.want))
		}
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		r.cont("a check copied from phase 8 or 9 fails on a correct phase 10:")
		r.cont("`otherfile` went at phase 8, E447 SURVIVED phase 8 and reaches")
		r.cont("zero here, `fileinfo` keeps three callers, E32 keeps its")
		r.cont(`speaker, and "[No Name]" occurs twice and both are live.`)
		return harness.ErrReported
	}
	r.say(`kept: buf_spname 5 and buf_get_fname 3 -- "[No Name]" is now the ONLY name a buffer has, not one of two -- get_trans_bufname 4, fileinfo 3 (CTRL-G, g CTRL-G and the startup message), check_fname 3 with E32`)
	r.cont("left and named rather than folded: BF_NOTEDITED and BF_NEW, read by fileinfo() and settable by nothing now that setfname() has gone, and b_shortname, which was already write-only before this phase")
	r.cont("the later phases' line: check_changed 4 and no_write_message 3 (the :q phase's), p_ur 2 and p_ro 2 with their rows (the options phase's), read_cmd_fd 12, vim_fsync 3, scriptin 8, redir_fd 6")
	r.cont("table: 99 -> 98 rows, names() reads 98, static_assert in place, the floor is 80 and the checked parser accepts it")

	// --- 3. the compile, the linkage and the libc surface --------------------
	before := strings.Fields(readFile(filepath.Join(state, "symbols", "undefined")))
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	after := strings.Fields(readFile(".cache/symbols/last/undefined"))
	goneU, cameU := comm23(before, after), comm23(after, before)
	if strings.Join(goneU, "\n") != "getcwd\nstat\nstrerror" || len(cameU) > 0 {
		r.say("the libc surface did not move by exactly getcwd, stat and strerror:")
		r.cont("  gone: %s ", strings.Join(goneU, " "))
		r.cont("  came: %s ", strings.Join(cameU, " "))
		return harness.ErrReported
	}
	for _, keep := range []string{"fsync", "read", "close", "dup"} {
		if !contains(after, keep) {
			return stop("%s went, and it is not this phase's: read, close and dup are the terminal's and fsync is ui_write's", keep)
		}
	}
	for _, absent := range []string{"open", "access", "fcntl", "stat", "getcwd", "strerror",
		"chmod", "fchmod", "fstat", "lstat", "unlink"} {
		if contains(after, absent) {
			return stop("%s is undefined again, and nothing here may add one", absent)
		}
	}
	r.say("symbols %s -> %s, and the set is exactly getcwd stat strerror -- with open, access and fcntl still absent, the core can no longer acquire a file descriptor at all; read, close, dup and fsync stay and are the terminal's and ui_write's",
		strings.TrimSpace(readFile(".cache/symbols/last/before")),
		strings.TrimSpace(readFile(".cache/symbols/last/after")))

	// --- 4. the enumerators --------------------------------------------------
	evOld, evNew := filepath.Join(tmp, "ev.old"), filepath.Join(tmp, "ev.new")
	var ewg sync.WaitGroup
	ewg.Add(1)
	go func() { defer ewg.Done(); exec.Command("sh", "tools/enumvals.sh", filepath.Join(state, "old.c"), evOld).Run() }()
	exec.Command("sh", "tools/enumvals.sh", f, evNew).Run()
	ewg.Wait()
	if err := z10Enums(r, readFile(evOld), readFile(evNew)); err != nil {
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

	if err := z10Probes(r, old, bin); err != nil {
		return err
	}
	return z10Pty(r, old, bin)
}

// z10Enums: EIGHTY-FIVE SURVIVORS RENUMBER and every one must be a CMD_.  85
// movers from one family is the case CLAUDE.md says a build is happy to get
// wrong.
func z10Enums(r *rep, oldTxt, newTxt string) error {
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
	var gone, came, moved, stray, bad []string
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
	for _, k := range moved {
		if !strings.HasPrefix(k, "CMD_") {
			stray = append(stray, k)
		}
	}
	for _, k := range gone {
		ok := contains(z10Families, k)
		for _, p := range z10Prefix {
			if strings.HasPrefix(k, p) {
				ok = true
			}
		}
		if !ok {
			bad = append(bad, k)
		}
	}
	if len(came) > 0 || len(stray) > 0 || len(bad) > 0 {
		if len(came) > 0 {
			r.say("enumerators arrived: %s", strings.Join(came, " "))
		}
		if len(stray) > 0 {
			r.say("enumerators outside CMD_ moved value: %s", strings.Join(stray, " "))
		}
		if len(bad) > 0 {
			r.say("enumerators went that this phase does not account for: %s", strings.Join(bad, " "))
		}
		return harness.ErrReported
	}
	if len(moved) == 0 {
		r.say("no survivor renumbered, and removing a cmdnames[] row must move every CMD_ after it -- the dump is not of this phase")
		return harness.ErrReported
	}
	r.say("enumerators %d -> %d: %d gone, %d renumbered and every one of the %d a CMD_, none arriving -- which is exactly the case a build is happy to get wrong",
		len(o), len(n), len(gone), len(moved), len(moved))
	return nil
}

var _ = io.Discard
