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

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero12", Zero12) }

var z12Gone = []string{"b_p_ro", "b_p_fs", "b_did_warn", "change_warning", "did_set_readonly",
	"w_readonly", "SHM_RO", "BV_RO", "BV_FS", "p_fs", "p_ro", "p_ur", "p_write", "p_wa", "p_prompt"}

var z12GoneStrings = []string{"W10: Warning: Changing a readonly file", "[RO]", "[readonly]"}

var z12Went = []string{"fsync", "prompt", "readonly", "undoreload", "write", "writeany"}

var z12Kept = map[string]int{
	"scriptin": 8, "redir_fd": 6, "vim_fsync": 3, "read_cmd_fd": 12,
	"bufIsChanged": 7, "curbufIsChanged": 6, "fileinfo": 3, "win_redr_status": 5,
}

const (
	z12CPO = `return did_set_option_listflag(*varp, (char_u *) "aAbBcCdDeEfFgHiIjJkKlLmMnoOpPqrRsStuvwWxXyZz$!%*-+<>#{|&/\\.;~" , args->os_errbuf, args->os_errbuflen);`
	z12SHM = `return did_set_option_listflag(*varp, (char_u *) "rmfixlnwaWtToOsAIcCqFSu" , args->os_errbuf, args->os_errbuflen);`
	z12CPOList = `aAbBcCdDeEfFgHiIjJkKlLmMnoOpPqrRsStuvwWxXyZz$!%*-+<>#{|&/\.;~`
	z12SHMList = "rmfixlnwaWtToOsAIcCqFSu"
)

var (
	z12RowRe  = regexp.MustCompile(`(?m)^[ \t]*\{"([a-z]+)",`)
	z12GlobRe = regexp.MustCompile(`&(p_[a-z0-9_]+)\b`)
	z12WhiteRe = regexp.MustCompile(`(?s)modeline_whitelist\[\][^;]*?\{(.*?)\n\};`)
	z12Fmt    = regexp.MustCompile(`"\\"%s%s%s%s%s", curbufIsChanged\(\)`)
)

// Zero12 is phase 12's check: the options nothing reads.
//
// EVERY VISIBLE EFFECT OF THIS PHASE IS OUTSIDE THE INSTRUMENT: no recorded
// case or row asks any of the six, bare `:set` does not move, and zexcmds
// keeps no stream digest for the `set` row.  The probes are not a supplement,
// they are the check.
func Zero12(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero12 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "noopts", w: w}
	f := filepath.Join(work, "zero-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	src, err := os.ReadFile(f)
	if err != nil {
		return err
	}
	newT, oldT := string(src), readFile(filepath.Join(state, "old.c"))
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	tmp, err := os.MkdirTemp("", "zero12")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)

	// --- 1. what went --------------------------------------------------------
	for _, g := range z12Gone {
		if n := countWord(src, g); n != 0 {
			return stop("'%s' still has %d mentions", g, n)
		}
	}
	for _, g := range z12GoneStrings {
		if n := countLinesWith(src, g); n != 0 {
			return stop("the string '%s' still has %d mentions", g, n)
		}
	}
	r.say("six option globals, two buffer-local fields, b_did_warn, change_warning, did_set_readonly, w_readonly, SHM_RO, BV_RO and BV_FS at 0 mentions, with W10 and both [RO] indicators -- the two functions by name and with the reason, the rest the sweep's")

	// --- 2. and everything that must NOT be at zero --------------------------
	var fail []string
	count := func(t, name string) int {
		return len(regexp.MustCompile(`\b` + regexp.QuoteMeta(name) + `\b`).FindAllString(t, -1))
	}
	table := func(t string) string {
		i := strings.Index(t, "static struct vimoption options[]")
		if i < 0 {
			return ""
		}
		j := strings.Index(t[i:], "\n};")
		if j < 0 {
			return t[i:]
		}
		return t[i : i+j]
	}
	set := func(re *regexp.Regexp, t string) map[string]bool {
		m := map[string]bool{}
		for _, x := range re.FindAllStringSubmatch(t, -1) {
			m[x[1]] = true
		}
		return m
	}
	rowsOld, rowsNew := set(z12RowRe, table(oldT)), set(z12RowRe, table(newT))
	wentGot, cameGot := keysNotIn(rowsOld, rowsNew), keysNotIn(rowsNew, rowsOld)
	if strings.Join(wentGot, " ") != strings.Join(z12Went, " ") || len(cameGot) > 0 {
		fail = append(fail, fmt.Sprintf("the option rows that went are %s and %s arrived; exactly %s must go",
			orNone(wentGot), orNone(cameGot), strings.Join(z12Went, " ")))
	}
	gOld, gNew := set(z12GlobRe, table(oldT)), set(z12GlobRe, table(newT))
	if len(gOld) != 102 || len(gNew) != 96 {
		fail = append(fail, fmt.Sprintf("the distinct option globals went %d -> %d, expected 102 -> 96", len(gOld), len(gNew)))
	}
	if m := z12WhiteRe.FindStringSubmatch(newT); m != nil {
		for _, name := range z12Went {
			if strings.Contains(m[1], `"`+name+`"`) {
				fail = append(fail, fmt.Sprintf("%s is still in modeline_whitelist[], which outlives the option it names", cutilRepr(name)))
			}
		}
	}
	if !rowsNew["modified"] || count(newT, "p_mod") != 2 || count(newT, "did_set_modified") != 3 {
		fail = append(fail, "'modified' moved: its row must stay, p_mod at 2 and did_set_modified at 3 -- decision 5 keeps it, and it is now the only option row with no reader of its own global")
	}
	if !rowsNew["paste"] || count(newT, "p_paste") != 12 {
		fail = append(fail, fmt.Sprintf("'paste' moved, and it is EXEMPT FOR EVER (ZERO-PLAN.md 2d): p_paste has %d mentions, expected 12", count(newT, "p_paste")))
	}
	for _, slot := range []string{"p_ai_nopaste", "p_et_nopaste", "p_sts_nopaste", "p_tw_nopaste", "p_wm_nopaste"} {
		if count(newT, slot) != 4 || count(oldT, slot) != 4 {
			fail = append(fail, fmt.Sprintf(`%s has %d mentions, expected 4 -- it is one of 'paste''s five save slots, which orphanopts.py reports and tolerates and which nothing here may "fix"`, slot, count(newT, slot)))
		}
	}
	for _, p := range []struct{ what, lit string }{{"'cpoptions'", z12CPO}, {"'shortmess'", z12SHM}} {
		if strings.Count(newT, p.lit) != 1 || strings.Count(oldT, p.lit) != 1 {
			fail = append(fail, fmt.Sprintf("%s's validity list is not the literal this phase was written against (%d in the input, %d here) -- it must be untouched, character for character",
				p.what, strings.Count(oldT, p.lit), strings.Count(newT, p.lit)))
		}
	}
	cpoI, shmI := z12Inert(newT, "CPO_", z12CPOList), z12Inert(newT, "SHM_", z12SHMList)
	cpoIOld, shmIOld := z12Inert(oldT, "CPO_", z12CPOList), z12Inert(oldT, "SHM_", z12SHMList)
	if cpoI != cpoIOld {
		fail = append(fail, fmt.Sprintf("the inert 'cpoptions' letters moved, %s -> %s, and this phase touches no CPO_", cutilRepr(cpoIOld), cutilRepr(cpoI)))
	}
	added, lost := runeDiff(shmI, shmIOld), runeDiff(shmIOld, shmI)
	if added != "r" || lost != "" {
		fail = append(fail, fmt.Sprintf("the inert 'shortmess' letters went %s -> %s; exactly `r` must be added, SHM_RO going with the [RO] indicator", cutilRepr(shmIOld), cutilRepr(shmI)))
	}
	names := make([]string, 0, len(z12Kept))
	for n := range z12Kept {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, name := range names {
		if k := count(newT, name); k != z12Kept[name] {
			fail = append(fail, fmt.Sprintf("%s has %d mentions, expected %d", name, k, z12Kept[name]))
		}
	}
	if !z12Fmt.MatchString(newT) {
		fail = append(fail, "fileinfo's CTRL-G format is not %s%s%s%s%s: the format string and the argument had to move together, and nothing in the build checks a vim_snprintf_safelen count")
	}
	for _, keep := range []string{"[Modified]", "[Not edited]", "[Read errors]", "[Help]", "[+]"} {
		if !strings.Contains(newT, keep) {
			fail = append(fail, fmt.Sprintf("%s went, and this phase removes only the read-only indicators", cutilRepr(keep)))
		}
	}
	rows := z6RowRe.FindAllString(newT, -1)
	got, _ := harness.CommandNamesIn(src, "zero-vim.c")
	if len(rows) != 98 || len(got) != 98 {
		fail = append(fail, fmt.Sprintf("cmdnames[] has %d rows and names() reads %d; both must be 98 -- this phase removes no command", len(rows), len(got)))
	}
	if !strings.Contains(newT, "static_assert(sizeof(cmdnames) / sizeof(cmdnames[0]) == CMD_SIZE") {
		fail = append(fail, "the static_assert on the row count went")
	}
	for _, name := range []string{"set", "quit", "registers"} {
		if !contains(got, name) {
			fail = append(fail, fmt.Sprintf(":%s went, and this phase removes no row", name))
		}
	}
	for _, p := range []struct {
		name string
		want int
	}{{"change_warning", 7}, {"did_set_readonly", 3}, {"b_p_ro", 10}, {"b_p_fs", 7}, {"b_did_warn", 4}, {"p_paste", 12}} {
		if count(oldT, p.name) != p.want {
			fail = append(fail, fmt.Sprintf("the input is not the file this phase was written against: %s %d, expected %d", p.name, count(oldT, p.name), p.want))
		}
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		r.cont("the seven rows with no reader are computed; SIX are dropped.")
		r.cont("'modified' is the seventh and decision 5 keeps it, and 'paste'")
		r.cont("is exempt for ever and is not in the set at all.")
		return harness.ErrReported
	}
	r.say("rows: 114 -> 108 and 102 -> 96 distinct globals, the set that went being exactly fsync prompt readonly undoreload write writeany, none arriving and none left in modeline_whitelist[]")
	r.cont("kept: 'modified' with p_mod 2 and did_set_modified 3 -- decision 5, and it is now the only row with no reader of its own global -- and 'paste' with p_paste 12 and its five save slots at four each, EXEMPT FOR EVER (ZERO-PLAN.md 2d)")
	r.cont("the two validity lists are untouched character for character; 23 of 'cpoptions' 60 letters and 14 of 'shortmess' 23 are inert, and this phase makes exactly one more so -- 'shortmess''s `r`")
	r.cont("the later phase's line: scriptin 8, redir_fd 6, vim_fsync 3; the table is 98 rows and untouched")

	// --- 3. the row floor, which this phase crosses --------------------------
	orphOld, errO := exec.Command("sh", "tools/st.sh", "orphanopts", filepath.Join(state, "old.c")).CombinedOutput()
	if errO != nil {
		r.say("orphanopts refuses the INPUT, so this phase is being checked against a file it was not written for")
		io.WriteString(w, string(orphOld))
		return harness.ErrReported
	}
	orphNew, errN := exec.Command("sh", "tools/st.sh", "orphanopts", f).CombinedOutput()
	if errN != nil {
		r.say("orphanopts refuses this source -- the row floor is no longer below 96, and that would fail the delta check of every zero phase after this one, not this one:")
		for _, l := range strings.Split(strings.TrimRight(string(orphNew), "\n"), "\n") {
			r.cont("  %s", l)
		}
		return harness.ErrReported
	}
	if string(orphOld) != string(orphNew) {
		r.say("orphanopts says something different about this source than about the input:")
		for _, l := range diffLines(string(orphOld), string(orphNew)) {
			r.cont("  %s", l)
		}
		return harness.ErrReported
	}
	r.say("the row floor is crossed and moved in this phase's own commit: orphanopts accepts 96 distinct globals and says exactly what it said about the input -- five non-pointer orphans, which are 'paste''s save slots, and every option pointer still has the row that sets it")

	// --- 4. the compile, the linkage and the libc surface --------------------
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
			return stop("%s went, and it is not this phase's: fclose, getc, putc and fsync are the FILE* phase's", keep)
		}
	}
	for _, absent := range []string{"open", "access", "fcntl", "stat", "getcwd", "strerror",
		"chmod", "fchmod", "fstat", "lstat", "unlink"} {
		if contains(after, absent) {
			return stop("%s is undefined again, and nothing here may add one", absent)
		}
	}
	r.say("symbols %s -> %s, the same set as a cmp -- an option row is not a libc call, and fsync is still reached from ui_write",
		strings.TrimSpace(readFile(".cache/symbols/last/before")),
		strings.TrimSpace(readFile(".cache/symbols/last/after")))

	// --- 5. the enumerators --------------------------------------------------
	evOld, evNew := filepath.Join(tmp, "ev.old"), filepath.Join(tmp, "ev.new")
	var ewg sync.WaitGroup
	ewg.Add(1)
	go func() { defer ewg.Done(); exec.Command("sh", "tools/enumvals.sh", filepath.Join(state, "old.c"), evOld).Run() }()
	exec.Command("sh", "tools/enumvals.sh", f, evNew).Run()
	ewg.Wait()
	if err := z12Enums(r, readFile(evOld), readFile(evNew)); err != nil {
		return err
	}

	// --- 6. the binary -------------------------------------------------------
	_ = exec.Command("make", "-C", work, "clean").Run()
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		(&rep{tag: "build", w: w}).say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	bin, _ := filepath.Abs(filepath.Join(work, "zero-vim"))
	old, _ := filepath.Abs(filepath.Join(state, "old"))
	now, _ := os.ReadFile(f)
	(&rep{tag: "build", w: w}).say("ok, %s -> %d lines, %d bytes", beforeLines, countLines(now), sizeOf(bin))

	return z12Probes(r, old, bin)
}

// z12Inert is the letters of a flag list that have no enumerator naming them:
// accepted by the validity check and acted on by nothing.
func z12Inert(text, prefix, letters string) string {
	have := map[rune]bool{}
	for _, m := range regexp.MustCompile(regexp.QuoteMeta(prefix)+`(\w+) = '(.)'`).FindAllStringSubmatch(text, -1) {
		have[[]rune(m[2])[0]] = true
	}
	var b strings.Builder
	for _, c := range letters {
		if !have[c] {
			b.WriteRune(c)
		}
	}
	return b.String()
}

func runeDiff(a, b string) string {
	in := map[rune]bool{}
	for _, c := range b {
		in[c] = true
	}
	seen := map[rune]bool{}
	var out []string
	for _, c := range a {
		if !in[c] && !seen[c] {
			seen[c] = true
			out = append(out, string(c))
		}
	}
	sort.Strings(out)
	return strings.Join(out, "")
}

func keysNotIn(a, b map[string]bool) []string {
	var out []string
	for k := range a {
		if !b[k] {
			out = append(out, k)
		}
	}
	sort.Strings(out)
	return out
}

func orNone(s []string) string {
	if len(s) == 0 {
		return "none"
	}
	return strings.Join(s, " ")
}

func z12Enums(r *rep, oldTxt, newTxt string) error {
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
	want := "BV_FS BV_RO SHM_RO"
	if strings.Join(gone, " ") != want || len(came) > 0 || len(moved) > 0 {
		if strings.Join(gone, " ") != want {
			r.say("the enumerators that went are %s, expected exactly %s", strings.Join(gone, " "), want)
		}
		if len(came) > 0 {
			r.say("enumerators arrived: %s", strings.Join(came, " "))
		}
		if len(moved) > 0 {
			r.say("survivors renumbered: %s -- BV_RO is unpinned and BV_SI is the next survivor, so this is the direction that goes wrong", strings.Join(moved, " "))
		}
		return harness.ErrReported
	}
	if n["BV_SI"] != o["BV_SI"] {
		r.say("BV_SI moved, and it is the survivor after BV_RO")
		return harness.ErrReported
	}
	r.say("enumerators %d -> %d: BV_FS, BV_RO and SHM_RO go, BV_SI keeps its value where deadenums.py pinned it, and NOT ONE OTHER SURVIVOR MOVED", len(o), len(n))
	return nil
}
