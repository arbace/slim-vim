package edit

import (
	"fmt"
	"io"
	"os"
	"regexp"
	"sort"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { registerArgs("zero36", Zero36) }

var (
	z36Dir     = regexp.MustCompile(`^ *# *`)
	z36Inc     = regexp.MustCompile(`^#include <[A-Za-z0-9_/.]+>$`)
	z36DeclRe  = regexp.MustCompile(`^[A-Za-z_][\w *]*\**\w+\([^;]*\);$`)
	z36Reraise = regexp.MustCompile(`^(\s*)kill\(getpid\(\), (\w+)\);$`)
	z36ProtoGP = regexp.MustCompile(`^static [\w *]+mch_get_pid\(.*\);$`)
	z36Write   = regexp.MustCompile(`^\s*long_to_char\(mch_get_pid\(\), (\w+)->b0_pid\);$`)
	z36Field   = regexp.MustCompile(`^\s*char_u\s+b0_pid\[\d+\];$`)
	z36Name    = regexp.MustCompile(`^.*?\**(\w+)\(.*$`)
	z36RetType = regexp.MustCompile(`^    [\w *]+$`)
)

// z36IsDecl is the phase's `DECL`, whose Python spells the exclusion as a
// NEGATIVE LOOKAHEAD -- `^(?!static |typedef |static_assert)...`.  RE2 has none,
// and the three prefixes are tested instead, which is exact here for the reason
// the byte tests elsewhere are: what is excluded is at the START of the line and
// is consumed by nothing.
func z36IsDecl(l string) bool {
	if strings.HasPrefix(l, "static ") || strings.HasPrefix(l, "typedef ") ||
		strings.HasPrefix(l, "static_assert") {
		return false
	}
	return z36DeclRe.MatchString(l)
}

// Zero36 leaves the core naming no libc function at all.  The last two go by
// DIFFERENT routes: `getpid` is avoidable outright, its one caller feeding a
// `b0_pid` that nothing reads; `kill` is moved, becoming host_raise(), which
// takes no pid because a core that cannot ask for its own process id must not be
// handed one.
func Zero36(text []byte, w io.Writer, args []string) ([]byte, error) {
	p := ph{"noclib", w}
	if len(args) != 1 {
		return nil, p.die("usage: edit zero36 <file> <state-dir>")
	}
	state := args[0]
	t := string(text)

	mentions := func(s, name string) int {
		return len(regexp.MustCompile(`\b`+name+`\b`).FindAllString(s, -1))
	}
	blankRuns := func(s string) int {
		L := strings.Split(s, "\n")
		n := 0
		for i := 1; i < len(L); i++ {
			if L[i] == "" && L[i-1] == "" {
				n++
			}
		}
		return n
	}
	swap := func(old, new, what, why string) error {
		if c := strings.Count(t, old); c != 1 {
			return p.die("%s occurs %d times, expected 1 -- %s", what, c, why)
		}
		t = strings.Replace(t, old, new, 1)
		return nil
	}
	// defn is the half-open line range of a definition in this tree's ONE shape,
	// the same shape zhostonly reads.
	defn := func(L []string, name string) (int, int, error) {
		head := regexp.MustCompile(`^` + name + `\s*\(`)
		var heads []int
		for i, l := range L {
			if head.MatchString(l) && i+1 < len(L) && L[i+1] == "{" {
				heads = append(heads, i)
			}
		}
		if len(heads) != 1 {
			return 0, 0, p.die("`%s` is defined %d times at column 0, and this phase needs exactly one",
				name, len(heads))
		}
		end := heads[0]
		for end < len(L) && L[end] != "}" {
			end++
		}
		if end >= len(L) {
			return 0, 0, p.die("`%s` does not close at column 0", name)
		}
		if !z36RetType.MatchString(L[heads[0]-1]) {
			return 0, 0, p.die("the line above `%s`'s head is %s and every definition in this tree carries "+
				"its return type there, indented", name, cutil.PyRepr(L[heads[0]-1]))
		}
		return heads[0] - 1, end + 1, nil
	}
	shortName := func(l string) string { return z36Name.ReplaceAllString(l, "$1") }

	L := strings.Split(t, "\n")
	linesBefore := len(L) - 1
	runsBefore := blankRuns(t)

	// ---- 0. the boundary, and the file this edit was written against ---------
	var directives []int
	for i, l := range L {
		if z36Dir.MatchString(l) {
			directives = append(directives, i)
		}
	}
	if len(directives) != 11 {
		return nil, p.die("the file holds %d preprocessor directives and this phase was written against "+
			"the eleven `#include`s phase 21 left", len(directives))
	}
	for i := range directives {
		if directives[i] != directives[0]+i {
			return nil, p.die("the eleven directives are not eleven consecutive lines")
		}
	}
	for _, i := range directives {
		if !z36Inc.MatchString(L[i]) {
			return nil, p.die("a directive is not an `#include <...>` of a system header, and no phase may " +
				"add one")
		}
	}
	boundary := directives[0]
	p.sayf("the boundary is line %d, the first of the eleven `#include`s, and there is not a "+
		"directive above it", boundary+1)

	// ---- 1. the core's block of ordinary declarations, FOUND rather than assumed
	var seed []int
	for i, l := range L[:boundary] {
		if l == z36Go[0] {
			seed = append(seed, i)
		}
	}
	if len(seed) != 1 {
		return nil, p.die("the core does not declare `%s` exactly once, so this phase has not been handed "+
			"the file it was written for", z36Go[0])
	}
	lo, hi := seed[0], seed[0]
	for lo > 0 && z36IsDecl(L[lo-1]) {
		lo--
	}
	for hi+1 < boundary && z36IsDecl(L[hi+1]) {
		hi++
	}
	blockBefore := append([]string{}, L[lo:hi+1]...)
	for _, line := range z36Go {
		if !contains(blockBefore, line) {
			return nil, p.die("`%s` is not in the core's block of ordinary declarations, which is %s",
				line, strings.Join(blockBefore, " / "))
		}
	}
	if L[lo-1] != "" || L[hi+1] != "" {
		return nil, p.die("the block is not a paragraph of its own -- line %d is %s and line %d is %s",
			lo, cutil.PyRepr(L[lo-1]), hi+2, cutil.PyRepr(L[hi+1]))
	}
	var blockAfter []string
	for _, l := range blockBefore {
		if !contains(z36Go, l) {
			blockAfter = append(blockAfter, l)
		}
	}
	names := make([]string, len(blockBefore))
	for i, l := range blockBefore {
		names[i] = shortName(l)
	}
	p.sayf("the core's block of ordinary declarations is lines %d-%d, %d of them: %s",
		lo+1, hi+1, len(blockBefore), strings.Join(names, " "))

	// ---- 2. the two names above the boundary, AS A PARTITION AND NOT A COUNT -
	core := strings.Join(L[:boundary], "\n")
	host := strings.Join(L[boundary:], "\n")
	gpLo, gpHi, err := defn(L, "mch_get_pid")
	if err != nil {
		return nil, err
	}
	if gpHi > boundary {
		return nil, p.die("mch_get_pid() is defined below the boundary, and this phase is about what the " +
			"CORE says")
	}
	var raiseLines []int
	for i := 0; i < boundary; i++ {
		if z36Reraise.MatchString(L[i]) {
			raiseLines = append(raiseLines, i)
		}
	}
	if len(raiseLines) != 1 {
		return nil, p.die("`kill(getpid(), <name>);` is %d lines above the boundary and this phase needs "+
			"exactly one, the deferred deadly signal vim_handle_signal() re-raises", len(raiseLines))
	}
	rl := raiseLines[0]
	m := z36Reraise.FindStringSubmatch(L[rl])
	indent, deferred := m[1], m[2]
	gpRange := make([]int, 0, gpHi-gpLo)
	for i := gpLo; i < gpHi; i++ {
		gpRange = append(gpRange, i)
	}
	type class struct {
		what  string
		lines []int
	}
	classes := []struct {
		name string
		cls  []class
	}{
		{"getpid", []class{
			{"declaration", []int{lo + indexOf(blockBefore, z36Go[0])}},
			{"mch_get_pid()", gpRange},
			{"the re-raise", []int{rl}},
		}},
		{"kill", []class{
			{"declaration", []int{lo + indexOf(blockBefore, z36Go[1])}},
			{"the re-raise", []int{rl}},
		}},
	}
	// The Python iterates a dict, whose order is the insertion order; the report
	// is what a port must reproduce, so the classes are a SLICE here and not a
	// map -- ranging a Go map would reorder the line every run.
	for _, c := range classes {
		word := regexp.MustCompile(`\b` + c.name + `\b`)
		var seen []int
		for i := 0; i < boundary; i++ {
			if word.MatchString(L[i]) {
				seen = append(seen, i)
			}
		}
		owned := map[int]bool{}
		for _, cl := range c.cls {
			for _, i := range cl.lines {
				owned[i] = true
			}
		}
		var stray []string
		for _, i := range seen {
			if !owned[i] {
				stray = append(stray, fmt.Sprintf("%d:%s", i+1, strings.TrimSpace(L[i])))
			}
		}
		if len(stray) > 0 {
			var labels []string
			for _, cl := range c.cls {
				labels = append(labels, cl.what)
			}
			return nil, p.die("`%s` is said above the boundary at %s, which is in none of the classes this "+
				"phase rewrites (%s) -- and this phase will not delete a declaration whose "+
				"every use it cannot account for",
				c.name, strings.Join(first(stray, 4), " "), strings.Join(labels, ", "))
		}
		var parts []string
		for _, cl := range c.cls {
			any := false
			var where []string
			for _, i := range cl.lines {
				if word.MatchString(L[i]) {
					any = true
					where = append(where, fmt.Sprintf("%d", i+1))
				}
			}
			if !any {
				return nil, p.die("the class `%s` of `%s` holds no mention of it", cl.what, c.name)
			}
			parts = append(parts, fmt.Sprintf("%s at %s", cl.what, strings.Join(where, " ")))
		}
		s := "s"
		if len(seen) == 1 {
			s = ""
		}
		p.sayf("`%s` above the boundary: %d mention%s, and every one falls in a class this "+
			"phase rewrites -- %s", c.name, len(seen), s, strings.Join(parts, ", "))
	}
	for _, nh := range []struct {
		name  string
		nhost int
	}{{"getpid", 0}, {"kill", 1}} {
		if k := mentions(host, nh.name); k != nh.nhost {
			return nil, p.die("`%s` has %d mentions below the boundary and this phase was written against "+
				"%d -- musl_suspend() stops the process group with `kill(0, SIGTSTP)` and "+
				"nothing below the boundary asks for a pid", nh.name, k, nh.nhost)
		}
	}
	_ = core
	if mentions(t, "host_raise") > 0 {
		return nil, p.die("`host_raise` is already a name in this file")
	}

	// ---- 3. getpid is AVOIDED -------------------------------------------------
	var protoGP, callers []int
	for i, l := range L {
		if z36ProtoGP.MatchString(l) {
			protoGP = append(protoGP, i)
		}
	}
	for i, l := range L {
		if len(callsNotAfterWord([]byte(l), "mch_get_pid")) > 0 &&
			!(gpLo <= i && i < gpHi) && !contains(protoGP, i) {
			callers = append(callers, i)
		}
	}
	if len(protoGP) != 1 || len(callers) != 1 {
		return nil, p.die("mch_get_pid() has %d forward declarations and %d call sites outside its own "+
			"definition, and this phase needs one of each -- the prototype tools/deadprotos.py "+
			"takes, and ml_open()'s write of b0_pid", len(protoGP), len(callers))
	}
	if !z36Write.MatchString(L[callers[0]]) {
		return nil, p.die("mch_get_pid()'s one call site is %s, and this phase was written against "+
			"ml_open()'s `long_to_char(mch_get_pid(), b0p->b0_pid);`", cutil.PyRepr(L[callers[0]]))
	}
	var b0, field []int
	b0Re := regexp.MustCompile(`\bb0_pid\b`)
	for i, l := range L {
		if b0Re.MatchString(l) {
			b0 = append(b0, i)
			if z36Field.MatchString(l) {
				field = append(field, i)
			}
		}
	}
	want := append(append([]int{}, field...), callers[0])
	sort.Ints(want)
	if len(b0) != 2 || len(field) != 1 || !sameInts(b0, want) {
		var shown []string
		for _, i := range b0 {
			shown = append(shown, fmt.Sprintf("%d:%s", i+1, strings.TrimSpace(L[i])))
		}
		return nil, p.die("`b0_pid` has %d mentions and this phase needs exactly two, its own declaration "+
			"and the one write: %s", len(b0), strings.Join(shown, " "))
	}
	p.sayf("`b0_pid` is WRITE-ONLY: %d mentions in the whole file, its declaration at line %d "+
		"and ml_open()'s write at line %d, and not one read.  So the write is the entry "+
		"point, mch_get_pid() (lines %d-%d) is its only feeder, and `getpid` leaves the core "+
		"without a host call", len(b0), field[0]+1, callers[0]+1, gpLo+1, gpHi)
	if err := swap(L[callers[0]]+"\n", "", "ml_open()'s write of b0_pid",
		"it is the only mention of the field that is not its declaration, and the only "+
			"caller of mch_get_pid()"); err != nil {
		return nil, err
	}
	if err := swap(strings.Join(L[gpLo:gpHi], "\n")+"\n\n", "", "mch_get_pid()'s definition",
		"its one caller has just gone, and its body is the only other place the core says "+
			"`getpid`"); err != nil {
		return nil, err
	}

	// ---- 4. kill is MOVED -----------------------------------------------------
	if err := swap(fmt.Sprintf("%skill(getpid(), %s);\n", indent, deferred),
		fmt.Sprintf("%shost_raise(%s);\n", indent, deferred),
		"vim_handle_signal()'s re-raise of a deferred deadly signal",
		"the core asks the host to raise the signal on this process; WHICH process that is "+
			"is the host's idea, exactly as fd 1 is under host_write"); err != nil {
		return nil, err
	}

	// ---- 5. the two declarations leave the core's block -----------------------
	// AS ONE REPLACEMENT OF THE WHOLE BLOCK, because of what happens when it
	// empties: the block is a paragraph, and taking its last line away leaves two
	// blank lines in a row.
	oldBlock := strings.Join(blockBefore, "\n") + "\n"
	dropped := 0
	if len(blockAfter) > 0 {
		if err := swap(oldBlock, strings.Join(blockAfter, "\n")+"\n",
			"the core's block of declarations",
			"the two this phase owns come out of it and the rest stay where they are"); err != nil {
			return nil, err
		}
		dropped = len(z36Go)
	} else {
		if err := swap(oldBlock+"\n", "", "the core's block of declarations AND its trailing "+
			"blank line",
			"the block is empty now, and a paragraph separator with nothing to separate "+
				"is the run of two blank lines this file does not have"); err != nil {
			return nil, err
		}
		dropped = len(blockBefore) + 1
	}

	// ---- 6. one prototype at the end of the core -> host block ---------------
	if err := swap("static long host_time(void);\n",
		"static long host_time(void);\n"+z36Proto+"\n",
		"the last of the core -> host prototypes",
		"the boundary is ONE block, and this belongs at the end of it rather than wherever "+
			"a declaration happened to fit"); err != nil {
		return nil, err
	}

	// ---- 7. and the host defines it, INSIDE the host block -------------------
	if err := swap("    static void\nmusl_suspend(void)\n{\n",
		z36Def+"    static void\nmusl_suspend(void)\n{\n",
		"musl_suspend()'s head, the last function of the host region",
		"the definition goes immediately above it, so that it is INSIDE the region "+
			"zhostonly reads and its two host words are where every other one is"); err != nil {
		return nil, err
	}

	// ---- 8. what the file is now ----------------------------------------------
	L = strings.Split(t, "\n")
	boundary = -1
	for i, l := range L {
		if z36Dir.MatchString(l) {
			boundary = i
			break
		}
	}
	core, host = strings.Join(L[:boundary], "\n"), strings.Join(L[boundary:], "\n")
	for _, r := range []struct {
		name         string
		ncore, nhost int
	}{{"getpid", 0, 1}, {"kill", 0, 2}, {"mch_get_pid", 1, 0}} {
		if mentions(core, r.name) != r.ncore || mentions(host, r.name) != r.nhost {
			return nil, p.die("`%s` ends at %d mentions above the boundary and %d below, expected %d and "+
				"%d", r.name, mentions(core, r.name), mentions(host, r.name), r.ncore, r.nhost)
		}
	}
	if k := mentions(t, "host_raise"); k != 3 {
		return nil, p.die("`host_raise` has %d mentions and it must have three -- its prototype, the one "+
			"call site it took over from `kill` and its definition", k)
	}
	if k := mentions(t, "b0_pid"); k != 1 {
		return nil, p.die("`b0_pid` has %d mentions and the edit leaves exactly one, its own declaration, "+
			"for tools/deadfields.py to take", k)
	}
	have := append([]string{}, L[lo:lo+len(blockAfter)]...)
	if strings.Join(have, "\x00") != strings.Join(blockAfter, "\x00") {
		return nil, p.die("the ordinary declarations left above the boundary are %s and the input's "+
			"block minus the two is %s", z36Or(have), z36Or(blockAfter))
	}
	if len(blockAfter) > 0 && (L[lo-1] != "" || L[lo+len(blockAfter)] != "") {
		return nil, p.die("what is left of the block is not a paragraph of its own")
	}
	var stray []string
	for i := 0; i < boundary; i++ {
		if z36IsDecl(L[i]) && (L[i-1] == "" || z36IsDecl(L[i-1])) &&
			!(lo <= i && i < lo+len(blockAfter)) {
			stray = append(stray, fmt.Sprintf("%d:%s", i+1, L[i]))
		}
	}
	if len(stray) > 0 {
		return nil, p.die("an ordinary declaration is above the boundary and outside the block: %s",
			strings.Join(first(stray, 4), " / "))
	}
	if err := os.WriteFile(state+"/block-before",
		[]byte(strings.Join(blockBefore, "\n")+"\n"), 0o644); err != nil {
		return nil, p.die("%v", err)
	}
	var after strings.Builder
	for _, l := range blockAfter {
		after.WriteString(l + "\n")
	}
	if err := os.WriteFile(state+"/block-after", []byte(after.String()), 0o644); err != nil {
		return nil, p.die("%v", err)
	}
	if len(blockAfter) > 0 {
		var left []string
		for _, l := range blockAfter {
			left = append(left, shortName(l))
		}
		p.sayf("the core's block of ordinary declarations is %d lines and was %d: %s remain, "+
			"and each is a libc function some LATER phase owns",
			len(blockAfter), len(blockBefore), strings.Join(left, " "))
	} else {
		p.sayf("THE CORE'S BLOCK OF ORDINARY DECLARATIONS IS EMPTY: it was %d lines and it is "+
			"now none.  Above the first `#include` there is no declaration that is not "+
			"`static`, and the check states what that means as a measurement of the cut "+
			"rather than as a sentence written here", len(blockBefore))
	}

	// DECLARATION BEFORE USE, COMPUTED, and the definition INSIDE the host region.
	var pr, df, uses []int
	for i, l := range L {
		if l == z36Proto {
			pr = append(pr, i)
		}
		if strings.HasPrefix(l, "host_raise(") && i+1 < len(L) && L[i+1] == "{" {
			df = append(df, i)
		}
	}
	for i, l := range L {
		if len(callsNotAfterWord([]byte(l), "host_raise")) > 0 &&
			!contains(pr, i) && !contains(df, i) {
			uses = append(uses, i)
		}
	}
	if len(pr) != 1 || len(df) != 1 || len(uses) != 1 {
		return nil, p.die("`host_raise` has %d prototypes, %d definitions and %d call sites",
			len(pr), len(df), len(uses))
	}
	var hb, he []int
	for i, l := range L {
		if strings.HasPrefix(l, "static volatile sig_atomic_t host_winch_pending") {
			hb = append(hb, i)
		}
		if strings.HasPrefix(l, "musl_suspend(") {
			he = append(he, i)
		}
	}
	if len(hb) != 1 || len(he) != 1 {
		return nil, p.die("the host region does not begin and end exactly once -- zhostonly reads " +
			"it from `host_winch_pending` to musl_suspend's last brace")
	}
	end := he[0]
	for end < len(L) && L[end] != "}" {
		end++
	}
	if !(pr[0] < uses[0] && uses[0] < df[0]) {
		return nil, p.die("`host_raise`: prototype at %d, call at %d, definition at %d -- the prototype "+
			"must be above the call and the definition below it", pr[0]+1, uses[0]+1, df[0]+1)
	}
	if !(boundary < df[0] && hb[0] <= df[0] && df[0] <= end) {
		return nil, p.die("`host_raise` is defined at line %d, and it must be below the boundary (%d) and "+
			"INSIDE the host region (%d-%d): its body says `kill` and `getpid`, and every "+
			"mention of a host word lives in that region",
			df[0]+1, boundary+1, hb[0]+1, end+1)
	}
	p.sayf("`host_raise`: prototype line %d, one call site at line %d, definition line %d, "+
		"which is below the boundary at %d and inside the %d-line host region "+
		"zhostonly reads", pr[0]+1, uses[0]+1, df[0]+1, boundary+1, end+1-hb[0])

	// ---- 9. the arithmetic, every term computed from what was found ----------
	added := 1 + len(strings.Split(z36Def, "\n")) - 1
	removed := 1 + (gpHi - gpLo) + 1 + dropped
	if len(L)-1 != linesBefore+added-removed {
		return nil, p.die("the file is %d lines and the input was %d -- expected %d: one prototype and a "+
			"%d-line definition in, and ml_open()'s write, mch_get_pid()'s %d lines with "+
			"the blank after it and %d out of the core's block",
			len(L)-1, linesBefore, linesBefore+added-removed, added-1, gpHi-gpLo, dropped)
	}
	if r := blankRuns(t); r != runsBefore {
		return nil, p.die("the edit left %d runs of two blank lines where there were %d", r, runsBefore)
	}
	var d2 []int
	for i, l := range L {
		if z36Dir.MatchString(l) {
			d2 = append(d2, i)
		}
	}
	okd := len(d2) == 11 && d2[0] == boundary
	for i := range d2 {
		if d2[i] != d2[0]+i {
			okd = false
		}
	}
	if !okd {
		return nil, p.die("the output does not have the same eleven contiguous `#include` directives -- " +
			"this phase adds a DECLARATION and a DEFINITION, never a directive")
	}
	p.sayf("%d -> %d lines before the sweep, the eleven #includes untouched at line %d, and no "+
		"run of two blank lines.  tools/deadprotos.py and tools/deadfields.py are left "+
		"`static long mch_get_pid(void);` and `b0_pid` to find",
		linesBefore, len(L)-1, boundary+1)
	return []byte(t), nil
}

// z36Or is Python's `' / '.join(xs) or 'none'`.
func z36Or(xs []string) string {
	if len(xs) == 0 {
		return "none"
	}
	return strings.Join(xs, " / ")
}

func sameInts(a, b []int) bool {
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
