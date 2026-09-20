package edit

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { registerArgs("zero27", Zero27) }

// ---- the twelve constants -----------------------------------------------
// Eight derived and four asserted.  The initialiser text is used TWICE -- as
// the enumerator above the boundary and as the left-hand side of the
// static_assert below it -- and it is written here ONCE, so the derivation and
// the thing that checks it cannot drift apart.  The check reads both back out
// of the output and requires them equal.
type z27Const struct{ ty, name, val string }

var z27Consts = []z27Const{
	{"int", "INT_MAX", "(int)(~0u >> 1)"},
	{"int", "INT_MIN", "-(int)(~0u >> 1) - 1"},
	{"long", "LONG_MAX", "(long)(~0ul >> 1)"},
	{"long", "LONG_MIN", "-(long)(~0ul >> 1) - 1"},
	{"long long", "LLONG_MAX", "(long long)(~0ull >> 1)"},
	{"long long", "LLONG_MIN", "-(long long)(~0ull >> 1) - 1"},
	{"unsigned long long", "ULLONG_MAX", "~0ull"},
	{"usize", "SIZE_MAX", "(usize)-1"},
	{"", "PATH_MAX", "4096"},
	{"", "EXIT_FAILURE", "1"},
	{"", "SIGHUP", "1"},
	{"", "SIGTERM", "15"},
}

const (
	z27Host    = "static volatile sig_atomic_t host_winch_pending"
	z27Typedef = "typedef typeof(sizeof(0)) usize;"
	z27VProto  = "static int vim_vsnprintf("
)

// The four that hold a `va_list`.  They are named because `va_list` is
// <stdarg.h>'s and the core cannot declare it; EVERYTHING ELSE that moves is
// computed from them.
var z27Variadic = []string{"vim_snprintf", "vim_vsnprintf", "skip_to_arg", "vim_vsnprintf_typval"}

// The other direction of the boundary: the host calls these, so they are
// unused ABOVE the cut by construction and stay there.  They are the stopping
// rule of the fixpoint.
var z27Keep = map[string]bool{"vim_main": true, "deathtrap": true}

var (
	z27Inc      = regexp.MustCompile(`^#include <([A-Za-z0-9_/.]+)>$`)
	z27Word     = regexp.MustCompile(`\b[A-Za-z_]\w*\b`)
	z27EnumHead = regexp.MustCompile(`^enum\b`)
	z27Ident    = regexp.MustCompile(`^\s*([A-Za-z_]\w*)`)
	z27Hash     = regexp.MustCompile(`^ *#`)
	z27HashInc  = regexp.MustCompile(`^ *# *include `)
	// gcc echoes the offending source line, and this file is full of strings
	// like "E685: Internal error: %s" -- so an error is recognised by its
	// POSITION in the diagnostic and never by the word.  Reading it the other
	// way makes every compile of this particular file look like a failure.
	z27Err     = regexp.MustCompile(`(?m)^[^ ].*:\d+:\d+: error:.*$`)
	z27Undecl  = regexp.MustCompile(`'(\w+)' undeclared`)
	z27Unknown = regexp.MustCompile(`unknown type name '(\w+)'`)
	z27DeadFn  = regexp.MustCompile(`'(\w+)' defined but not used \[-Wunused-function\]`)
	z27DeadVar = regexp.MustCompile(`'(\w+)' defined but not used \[-Wunused-variable\]`)
	z27Dead    = regexp.MustCompile(`'(\w+)' defined but not used`)
	z27Used    = regexp.MustCompile(`'(\w+)' used but never defined`)
)

type z27Item struct {
	kind string
	at   int
	body []string
}

type z27Enum struct {
	s, e  int
	names []string
	own   map[string]int
}

// Zero27 is the move: the eleven `#include`s go below the core, twelve
// header-supplied constants become enumerators asserted from below, and the
// formatter's private island follows the four `va_list` functions down.
func Zero27(text []byte, w io.Writer, args []string) ([]byte, error) {
	p := ph{"boundary", w}
	if len(args) != 1 {
		return nil, p.die("usage: edit zero27 <file> <state-dir>")
	}
	state := args[0]
	base := strings.Split(string(text), "\n")

	blankRuns := func(lines []string) int {
		n := 0
		for i := 1; i < len(lines); i++ {
			if lines[i] == "" && lines[i-1] == "" {
				n++
			}
		}
		return n
	}

	// ---- 0. the file this edit was written against ----------------------
	// ELEVEN DIRECTIVES, every one an `#include` of a system header, on the
	// first eleven lines -- what phase 21 left and what phases 23 and 26 each
	// asserted in turn.  This is the LAST phase for which that sentence is
	// true, and making it false is the point.
	var dIdx []int
	var dLine []string
	for i, l := range base {
		if strings.HasPrefix(l, "#") {
			dIdx = append(dIdx, i)
			dLine = append(dLine, l)
		}
	}
	okFirst := len(dIdx) == 11
	for k, i := range dIdx {
		if okFirst && i != k {
			okFirst = false
		}
	}
	if !okFirst {
		var at []string
		for _, i := range dIdx {
			at = append(at, strconv.Itoa(i))
		}
		return nil, p.die("the input does not have exactly eleven preprocessor directives on its "+
			"first eleven lines: %d at %s", len(dIdx), strings.Join(at, " "))
	}
	var incNames []string
	for _, l := range dLine {
		m := z27Inc.FindStringSubmatch(l)
		if m == nil {
			return nil, p.die("a directive is not an `#include <...>` of a system header")
		}
		incNames = append(incNames, "<"+m[1]+">")
	}
	if base[11] != "" {
		return nil, p.die("the eleventh `#include` is not followed by a blank line, so the block " +
			"this edit lifts is not the shape it was written against")
	}
	var hb []int
	for i, l := range base {
		if strings.HasPrefix(l, z27Host) {
			hb = append(hb, i)
		}
	}
	if len(hb) != 1 {
		return nil, p.die("the host block does not begin exactly once with %s -- found %d.  It is "+
			"where the includes are going and there is nowhere else to put them",
			cutil.PyRepr(z27Host), len(hb))
	}
	nTypedef := 0
	for _, l := range base {
		if l == z27Typedef {
			nTypedef++
		}
	}
	if nTypedef != 1 {
		return nil, p.die("`%s` is not in the input exactly once -- phase 23 put it below the last "+
			"`#include` and the constants go beneath it", z27Typedef)
	}
	if k := blankRuns(base); k != 0 {
		return nil, p.die("the input already holds %d runs of two blank lines, and this edit "+
			"empties whole paragraphs -- it can only preserve a zero", k)
	}
	p.sayf("eleven directives, every one an `#include <...>` on the first eleven lines, "+
		"the host block beginning exactly once, and not one run of two blank lines: %s",
		strings.Join(incNames, " "))

	// ---- 1. the four kinds of thing that can move ------------------------

	// fspan: a function definition, the `    static T` line through the `}`
	// at column 0.
	fspan := func(n string) (int, int, error) {
		var i []int
		for k, l := range base {
			if strings.HasPrefix(l, n+"(") {
				i = append(i, k)
			}
		}
		if len(i) != 1 {
			return 0, 0, p.die("`%s` is not defined exactly once at column 0 -- found %d", n, len(i))
		}
		s := i[0] - 1
		if !strings.HasPrefix(base[s], "    static ") {
			return 0, 0, p.die("`%s` is not preceded by its `    static T` line: %s",
				n, cutil.PyRepr(base[s]))
		}
		e := i[0]
		for base[e] != "}" {
			e++
		}
		if base[e+1] != "" {
			return 0, 0, p.die("`%s` is not followed by a blank line", n)
		}
		return s, e, nil
	}

	// ospan: a file-scope object, one line.
	ospan := func(n string) (int, int, error) {
		re := regexp.MustCompile(`^static [^(=]*\b` + n + `\b`)
		var i []int
		for k, l := range base {
			if re.MatchString(l) {
				i = append(i, k)
			}
		}
		if len(i) != 1 {
			return 0, 0, p.die("`%s` is not declared at file scope exactly once -- found %d", n, len(i))
		}
		return i[0], i[0], nil
	}

	// espan: an enum block, the `enum` head through the line holding its `};`.
	espan := func(first int) (int, int, error) {
		e := first
		for !strings.Contains(base[e], "};") {
			e++
			if e-first > 512 || e >= len(base) {
				return 0, 0, p.die("the enum block at line %d does not close within 512 lines", first+1)
			}
		}
		return first, e, nil
	}

	enumNames := func(s, e int) []string {
		body := strings.Join(base[s:e+1], "\n")
		body = body[strings.Index(body, "{")+1 : strings.LastIndex(body, "}")]
		var out []string
		for _, part := range strings.Split(body, ",") {
			if m := z27Ident.FindStringSubmatch(part); m != nil {
				out = append(out, m[1])
			}
		}
		return out
	}

	countWords := func(s string) map[string]int {
		c := map[string]int{}
		for _, m := range z27Word.FindAllString(s, -1) {
			c[m]++
		}
		return c
	}

	// Every enum block above the host block, read once, with its own names
	// counted inside its own body.  An enumerator is invisible to every
	// warning gcc has (CLAUDE.md), so a block only the moved code names has to
	// be found by counting rather than by compiling -- and the counting is
	// done with one word histogram per round, not one regex per name, because
	// there are seven hundred blocks and two megabytes of text.
	var enums []z27Enum
	for i := 12; i < hb[0]; {
		if z27EnumHead.MatchString(base[i]) {
			s, e, err := espan(i)
			if err != nil {
				return nil, err
			}
			enums = append(enums, z27Enum{s, e, enumNames(s, e),
				countWords(strings.Join(base[s:e+1], "\n"))})
			i = e + 1
		} else {
			i++
		}
	}
	if len(enums) < 400 {
		return nil, p.die("only %d enum blocks were found above the host block, where this file is "+
			"written almost entirely in them -- the head pattern has stopped matching "+
			"and every dead one below would go unnoticed", len(enums))
	}
	ename := map[int]string{}
	for _, en := range enums {
		if len(en.names) > 0 {
			ename[en.s] = en.names[0]
		} else {
			ename[en.s] = "?"
		}
	}

	var p0s []int
	for i, l := range base {
		if strings.HasPrefix(l, z27VProto) {
			p0s = append(p0s, i)
		}
	}
	if len(p0s) != 1 || !strings.HasSuffix(strings.TrimSpace(base[p0s[0]+3]), ";") ||
		base[p0s[0]-1] != "" || base[p0s[0]+4] != "" {
		return nil, p.die("the two `va_list` prototypes are not the four-line block between blank " +
			"lines this edit lifts")
	}
	p0 := p0s[0]

	// build: the whole file, with funcs, objs and enums moved below the
	// includes.
	build := func(funcs, objs []string, moveEnums []int, consts bool) ([]string, int, map[int]bool, error) {
		drop := map[int]bool{}
		for i := 0; i < 12; i++ {
			drop[i] = true
		}
		for i := p0 - 1; i < p0+4; i++ {
			drop[i] = true
		}
		var items []z27Item
		for _, n := range funcs {
			s, e, err := fspan(n)
			if err != nil {
				return nil, 0, nil, err
			}
			for i := s; i < e+2; i++ {
				drop[i] = true
			}
			items = append(items, z27Item{"f", s, base[s : e+1]})
		}
		for _, n := range objs {
			s, e, err := ospan(n)
			if err != nil {
				return nil, 0, nil, err
			}
			drop[s] = true
			items = append(items, z27Item{"o", s, base[s : e+1]})
		}
		for _, st := range moveEnums {
			s, e, err := espan(st)
			if err != nil {
				return nil, 0, nil, err
			}
			for i := s; i <= e; i++ {
				drop[i] = true
			}
			items = append(items, z27Item{"e", s, base[s : e+1]})
		}
		sort.SliceStable(items, func(i, j int) bool { return items[i].at < items[j].at })

		low := append([]string{}, base[0:11]...)
		low = append(low, "")
		if consts {
			for _, c := range z27Consts {
				low = append(low, fmt.Sprintf("static_assert(%s == %s, \"%s\");", c.val, c.name, c.name))
			}
			low = append(low, "")
		}
		for _, k := range []string{"e", "o"} {
			got := 0
			for _, it := range items {
				if it.kind != k {
					continue
				}
				got++
				low = append(low, it.body...)
				if k == "e" {
					low = append(low, "")
				}
			}
			if got > 0 && k == "o" {
				low = append(low, "")
			}
		}
		low = append(low, base[p0:p0+4]...)
		low = append(low, "")
		for _, it := range items {
			if it.kind == "f" {
				low = append(low, it.body...)
				low = append(low, "")
			}
		}

		var up []string
		if consts {
			for _, c := range z27Consts {
				if c.ty == "" {
					up = append(up, fmt.Sprintf("enum { %s = %s };", c.name, c.val))
				} else {
					up = append(up, "enum :",
						fmt.Sprintf("    %s { %s = %s };", c.ty, c.name, c.val))
				}
			}
		}

		var o []string
		for i, l := range base {
			if i == hb[0] {
				o = append(o, low...)
			}
			if drop[i] {
				continue
			}
			o = append(o, l)
			if consts && l == z27Typedef {
				o = append(o, "")
				o = append(o, up...)
			}
		}
		// A paragraph whose every line went leaves two blank lines meeting,
		// and CLAUDE.md allows no run of two -- nor can any verification tier
		// see one.
		var r []string
		collapsed := 0
		for _, l := range o {
			if l == "" && len(r) > 0 && r[len(r)-1] == "" {
				collapsed++
				continue
			}
			r = append(r, l)
		}
		return r, collapsed, drop, nil
	}

	cut := func(L []string) string {
		var o []string
		for _, l := range L {
			if z27HashInc.MatchString(l) {
				break
			}
			o = append(o, l)
		}
		for len(o) > 0 && o[len(o)-1] == "" {
			o = o[:len(o)-1]
		}
		return strings.Join(o, "\n") + "\n"
	}

	compileCut := func(L []string, name string) (string, error) {
		path := filepath.Join(state, name)
		if err := os.WriteFile(path, []byte(cut(L)), 0o644); err != nil {
			return "", p.die("the cut could not be written to %s: %v", path, err)
		}
		cmd := exec.Command("gcc", "-c", "-O0", "-fno-stack-protector", "-Wall",
			"-Wextra", "-Wno-unused-parameter", "-o", "/dev/null", path)
		var errb strings.Builder
		cmd.Stderr = &errb
		_ = cmd.Run()
		return errb.String(), nil
	}

	// ---- 2. the move, and the twelve names the compiler asks for ---------
	// THE LIST IS NOT REMEMBERED, IT IS ASKED FOR.  Move the includes and the
	// variadic layer, compile the cut ALONE, and collect every name it says
	// is undeclared.  That set must be exactly the twelve this phase
	// declares: a thirteenth would mean the core still takes something from a
	// header and phase 26 did not finish, and a missing one would mean this
	// program declares something nobody needs.
	l0, _, _, err := build(z27Variadic, nil, nil, false)
	if err != nil {
		return nil, err
	}
	w0, err := compileCut(l0, "cut0.c")
	if err != nil {
		return nil, err
	}
	askedSet := map[string]bool{}
	for _, m := range z27Undecl.FindAllStringSubmatch(w0, -1) {
		askedSet[m[1]] = true
	}
	for _, m := range z27Unknown.FindAllStringSubmatch(w0, -1) {
		askedSet[m[1]] = true
	}
	asked := sortedKeys(askedSet)
	var want []string
	for _, c := range z27Consts {
		want = append(want, c.name)
	}
	sort.Strings(want)
	if strings.Join(asked, "\x00") != strings.Join(want, "\x00") {
		shown := strings.Join(asked, " ")
		if shown == "" {
			shown = "(none)"
		}
		return nil, p.die("the cut asks for %d names and this phase declares %d.  Asked for: %s.  "+
			"Declared: %s.  A name in the first list and not the second is something "+
			"the core still takes from a header; one in the second and not the first "+
			"is a declaration nobody needs",
			len(asked), len(want), shown, strings.Join(want, " "))
	}
	core0 := strings.Join(base[11:hb[0]], "\n")
	counts := map[string]int{}
	for _, c := range z27Consts {
		counts[c.name] = len(regexp.MustCompile(`\b`+c.name+`\b`).FindAllString(core0, -1))
	}
	// Iterated in CONST order and not over the map: Python's dict keeps its
	// insertion order and a Go map would reorder this line every run.
	var missing []string
	for _, c := range z27Consts {
		if counts[c.name] < 1 {
			missing = append(missing, c.name)
		}
	}
	if len(missing) > 0 {
		return nil, p.die("a constant this phase declares does not occur above the host block at "+
			"all: %s", strings.Join(missing, " "))
	}
	p.sayf("the move alone leaves the cut with %d errors naming EXACTLY the twelve "+
		"constants this phase declares and nothing else", len(z27Err.FindAllString(w0, -1)))
	var shownCounts []string
	for _, c := range z27Consts {
		shownCounts = append(shownCounts, fmt.Sprintf("%s %d", c.name, counts[c.name]))
	}
	p.sayf("their counts above the host block, re-measured here: %s",
		strings.Join(shownCounts, "  "))

	// ---- 3. the fixpoint: whatever only the moved code uses --------------
	funcs := append([]string{}, z27Variadic...)
	var objs []string
	var moveEnums []int
	type round struct {
		nf, nv []string
		ne     []int
	}
	var rounds []round
	settled := false
	var collapsed int
	var L []string
	for r := 0; r < 16; r++ {
		Lr, _, drop, err := build(funcs, objs, moveEnums, true)
		if err != nil {
			return nil, err
		}
		wr, err := compileCut(Lr, "cutr.c")
		if err != nil {
			return nil, err
		}
		if e := z27Err.FindAllString(wr, -1); len(e) > 0 {
			if len(e) > 4 {
				e = e[:4]
			}
			return nil, p.die("the cut does not compile once the constants are in place:\n    %s",
				strings.Join(e, "\n    "))
		}
		nf := sortedMinus(z27DeadFn.FindAllStringSubmatch(wr, -1), z27Keep)
		nv := sortedMinus(z27DeadVar.FindAllStringSubmatch(wr, -1), z27Keep)
		// The enum blocks, counted on the text the cut actually is: a block
		// none of whose names occurs above the boundary outside its own body
		// belongs below it, exactly as a dead function does, and no warning
		// will ever say so.
		var kept []string
		for i, l := range base[:hb[0]] {
			if !drop[i] {
				kept = append(kept, l)
			}
		}
		above := countWords(strings.Join(kept, "\n"))
		moving := map[int]bool{}
		for _, s := range moveEnums {
			moving[s] = true
		}
		var ne []int
		for _, en := range enums {
			if moving[en.s] || drop[en.s] || len(en.names) == 0 {
				continue
			}
			all := true
			for _, n := range en.names {
				if above[n] != en.own[n] {
					all = false
					break
				}
			}
			if all {
				ne = append(ne, en.s)
			}
		}
		rounds = append(rounds, round{nf, nv, ne})
		if len(nf) == 0 && len(nv) == 0 && len(ne) == 0 {
			settled = true
			break
		}
		funcs = append(funcs, nf...)
		objs = append(objs, nv...)
		moveEnums = append(moveEnums, ne...)
	}
	if !settled {
		return nil, p.die("the fixpoint did not settle in 16 rounds")
	}
	L, collapsed, _, err = build(funcs, objs, moveEnums, true)
	if err != nil {
		return nil, err
	}

	// ---- 4. what the file is now -----------------------------------------
	wf, err := compileCut(L, "cut.c")
	if err != nil {
		return nil, err
	}
	if e := z27Err.FindAllString(wf, -1); len(e) > 0 {
		if len(e) > 4 {
			e = e[:4]
		}
		return nil, p.die("the finished cut does not compile:\n    %s", strings.Join(e, "\n    "))
	}
	bset := map[string]bool{}
	for _, m := range z27Used.FindAllStringSubmatch(wf, -1) {
		bset[m[1]] = true
	}
	boundary := sortedKeys(bset)
	left := sortedMinus(z27Dead.FindAllStringSubmatch(wf, -1), z27Keep)
	if len(left) > 0 {
		return nil, p.die("the fixpoint left %s unused above the boundary", strings.Join(left, " "))
	}
	var hashes []int
	for i, l := range strings.Split(cut(L), "\n") {
		if z27Hash.MatchString(l) {
			hashes = append(hashes, i)
		}
	}
	if len(hashes) > 0 {
		var at []string
		for _, i := range hashes {
			if len(at) < 5 {
				at = append(at, strconv.Itoa(i+1))
			}
		}
		return nil, p.die("%d lines above the boundary begin with a `#`, at %s",
			len(hashes), strings.Join(at, " "))
	}
	if k := blankRuns(L); k != 0 {
		return nil, p.die("the output holds %d runs of two blank lines", k)
	}
	var incAt []int
	for i, l := range L {
		if strings.HasPrefix(l, "#") {
			incAt = append(incAt, i)
		}
	}
	okAt := len(incAt) == 11
	for k, i := range incAt {
		if okAt && i != incAt[0]+k {
			okAt = false
		}
	}
	if !okAt {
		var at []string
		for _, i := range incAt {
			at = append(at, strconv.Itoa(i+1))
		}
		return nil, p.die("the output does not have exactly eleven directives on eleven "+
			"consecutive lines: %d at %s", len(incAt), strings.Join(at, " "))
	}

	var moved []string
	for _, n := range funcs {
		moved = append(moved, "func "+n)
	}
	for _, n := range objs {
		moved = append(moved, "obj "+n)
	}
	for _, s := range moveEnums {
		moved = append(moved, "enum "+strings.TrimSpace(base[s]))
	}
	if err := os.WriteFile(filepath.Join(state, "moved"),
		[]byte(strings.Join(moved, "\n")+"\n"), 0o644); err != nil {
		return nil, p.die("the moved list could not be written: %v", err)
	}
	if err := os.WriteFile(filepath.Join(state, "boundary"),
		[]byte(strings.Join(boundary, "\n")+"\n"), 0o644); err != nil {
		return nil, p.die("the boundary list could not be written: %v", err)
	}

	p.sayf("the fixpoint settled in %d rounds: %d functions, %d objects and %d enum "+
		"blocks go below the boundary, and every one after the four that hold a "+
		"`va_list` was named by gcc or counted, never by this program",
		len(rounds), len(funcs), len(objs), len(moveEnums))
	for i, r := range rounds {
		if len(r.nf) > 0 || len(r.nv) > 0 || len(r.ne) > 0 {
			var parts []string
			parts = append(parts, r.nf...)
			parts = append(parts, r.nv...)
			for _, s := range r.ne {
				parts = append(parts, "enum{"+ename[s]+"}")
			}
			p.sayf("  round %d: %s", i, strings.Join(parts, " "))
		}
	}
	p.sayf("%d lines -> %d, %d blank line(s) collapsed where an emptied paragraph left "+
		"two, the eleven `#include`s now at lines %d-%d, and NOTHING above them begins "+
		"with a `#`", len(base)-1, len(L)-1, collapsed, incAt[0]+1, incAt[len(incAt)-1]+1)
	p.sayf("THE CUT IS %d LINES, COMPILES WITH 0 ERRORS AND NOTHING ABOVE IT IS DEAD, "+
		"and its whole warning set is the boundary: %d names, every one `used but "+
		"never defined` -- %s",
		len(strings.Split(cut(L), "\n"))-1, len(boundary), strings.Join(boundary, " "))
	return []byte(strings.Join(L, "\n")), nil
}

func sortedMinus(ms [][]string, minus map[string]bool) []string {
	set := map[string]bool{}
	for _, m := range ms {
		if !minus[m[1]] {
			set[m[1]] = true
		}
	}
	return sortedKeys(set)
}
