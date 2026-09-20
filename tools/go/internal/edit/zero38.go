package edit

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"sort"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { phases["zero38"] = Zero38 }

// THE ONLY THING WRITTEN DOWN IN THIS PHASE.  Everything else is computed from
// it and from the source: which rows go, which capability tables die, which
// literals have to be rewritten and what the fallback may name.
var zero38Keep = []string{"xterm-256color", "debug"}

var (
	zero38Row    = regexp.MustCompile(`(?m)^[ \t]*\{\s*"([^"]*)"\s*,\s*(\w+)\s*\},\n`)
	zero38IfCall = regexp.MustCompile(`^\s*if\s*\(`)
	zero38Len    = regexp.MustCompile(`^[\s)]*,\s*\(\d+\)`)
)

// zero38Mentions counts an IDENTIFIER with string literals excluded.
//
// `builtin_xterm` is written inside a string literal as well as being a table,
// and a count that read that as a reference would report a dead table as live.
// That is why this blanks and p.mentions does not.
func zero38Mentions(text []byte, name string) int {
	return len(regexp.MustCompile(`\b`+regexp.QuoteMeta(name)+`\b`).
		FindAll(cutil.Blank(text), -1))
}

type zero38Edit struct {
	a, z int
	rep  string
}

// Zero38 takes the terminal vocabulary: builtin_terminals[] goes from ten rows
// to two, with three capability tables, find_builtin_term()'s xterm-family
// clause and a repair to set_termname()'s no-screen fallback.
func Zero38(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"terms", w}
	b := cutil.Blank(text)

	lineOf := func(off int) int { return bytes.Count(text[:off], []byte{'\n'}) + 1 }
	defspan := func(name string) (int, int, error) {
		a, z, ok := cutil.FindDefinition(text, b, name)
		if !ok {
			return 0, 0, p.die("%s() is not defined in this file, and the partition below is drawn "+
				"against its extent", name)
		}
		return a, z, nil
	}

	// ---- 0. the table, and the two rows that stay ------------------------
	i := bytes.Index(text, []byte("static builtin_tcap_T builtin_terminals[] = {"))
	if i < 0 {
		return nil, p.die("builtin_terminals[] is not in this file")
	}
	j := i + bytes.Index(text[i:], []byte("\n};"))
	type row struct {
		name, tab string
		a, z      int
	}
	var rows []row
	for _, m := range zero38Row.FindAllSubmatchIndex(text[i:j], -1) {
		rows = append(rows, row{
			name: string(text[i+m[2] : i+m[3]]),
			tab:  string(text[i+m[4] : i+m[5]]),
			a:    i + m[0], z: i + m[1],
		})
	}
	if len(rows) == 0 {
		return nil, p.die("builtin_terminals[] holds no row in the {\"name\", table} shape, so the cut " +
			"below would be vacuous")
	}
	var names []string
	for _, r := range rows {
		names = append(names, r.name)
	}
	if len(uniq(names)) != len(names) {
		return nil, p.die("builtin_terminals[] names a terminal twice: %s", strings.Join(names, " "))
	}
	var missing []string
	for _, k := range zero38Keep {
		if !containsStr(names, k) {
			missing = append(missing, k)
		}
	}
	if len(missing) > 0 {
		return nil, p.die("builtin_terminals[] does not name %s, and that is a row this phase keeps",
			strings.Join(missing, " "))
	}
	var gone []string
	for _, n := range names {
		if !containsStr(zero38Keep, n) {
			gone = append(gone, n)
		}
	}
	if len(gone) == 0 {
		return nil, p.die("builtin_terminals[] holds nothing but the two rows that stay: there is " +
			"nothing here to remove, and every assertion below would be vacuous")
	}
	p.sayf("builtin_terminals[] has %d rows.  %s stay and %d go -- %s.  The removed set is "+
		"the table MINUS the two, computed here, and the two are the only names this "+
		"phase writes down",
		len(rows), strings.Join(zero38Keep, " and "), len(gone), strings.Join(gone, " "))

	// ---- 1. THE PARTITION: every literal that IS a removed name ----------
	// cutil.Blank keeps offsets and blanks literal CONTENT, so a `"` left in
	// the blanked text is a real delimiter and the quotes pair up in order.
	// That is what makes this literal-aware: the identifier `builtin_xterm`,
	// the prefix inside `"screen.xterm"` and the substring of
	// `"xterm-256color"` are all invisible to it.
	var quotes []int
	for _, m := range regexp.MustCompile(`"`).FindAllIndex(b, -1) {
		quotes = append(quotes, m[0])
	}
	if len(quotes)%2 != 0 {
		return nil, p.die("the file has an odd number of string delimiters after blanking, so the " +
			"literal spans below cannot be trusted")
	}
	var lits [][2]int
	for k := 0; k+1 < len(quotes); k += 2 {
		lits = append(lits, [2]int{quotes[k], quotes[k+1]})
	}

	famA, famZ, err := defspan("find_builtin_term")
	if err != nil {
		return nil, err
	}
	fbA, fbZ, err := defspan("set_termname")
	if err != nil {
		return nil, err
	}
	pxA, pxZ, err := defspan("vim_is_xterm")
	if err != nil {
		return nil, err
	}
	classes := []struct {
		kind   string
		lo, hi int
	}{
		{"row", i, j},
		{"family", famA, famZ},
		{"fallback", fbA, fbZ},
		{"prefix", pxA, pxZ},
	}
	part := map[string][][2]int{}
	var loose [][2]int
	for _, s := range lits {
		if !containsStr(gone, string(text[s[0]+1:s[1]])) {
			continue
		}
		placed := false
		for _, c := range classes {
			if c.lo <= s[0] && s[0] < c.hi {
				part[c.kind] = append(part[c.kind], s)
				placed = true
				break
			}
		}
		if !placed {
			loose = append(loose, s)
		}
	}
	if len(loose) > 0 {
		var at []string
		for _, s := range loose {
			at = append(at, fmt.Sprintf("%s at line %d", cutil.PyRepr(string(text[s[0]+1:s[1]])), lineOf(s[0])))
		}
		return nil, p.die("%d literal(s) spell a removed terminal name outside builtin_terminals[], "+
			"find_builtin_term(), set_termname() and vim_is_xterm(), and this phase has "+
			"no class for them: %s", len(loose), strings.Join(at, ", "))
	}
	if len(part["row"]) != len(gone) {
		return nil, p.die("builtin_terminals[] holds %d literals spelling a removed name where %d "+
			"rows go", len(part["row"]), len(gone))
	}
	if len(part["family"]) != 1 || len(part["fallback"]) != 1 {
		return nil, p.die("find_builtin_term() spells a removed name %d times and set_termname() %d, "+
			"and this phase is written against one of each",
			len(part["family"]), len(part["fallback"]))
	}
	if len(part["prefix"]) == 0 {
		return nil, p.die("vim_is_xterm() spells no removed name, so the `prefix` class below would " +
			"be vacuous -- read the function before removing this")
	}
	// The `prefix` class is KEPT, and this is what makes keeping it honest:
	// each one must be an argument of a COUNTED comparison, so a name compared
	// in full could not sit here unnoticed.
	for _, s := range part["prefix"] {
		lo := s[0] - 80
		if lo < 0 {
			lo = 0
		}
		if !bytes.Contains(text[lo:s[0]], []byte("musl_strncasecmp")) {
			return nil, p.die("vim_is_xterm() compares %s other than as a counted prefix, so it is a "+
				"terminal NAME there and not five characters",
				cutil.PyRepr(string(text[s[0]+1:s[1]])))
		}
		hi := s[1] + 16
		if hi > len(text) {
			hi = len(text)
		}
		if !zero38Len.Match(text[s[1]+1 : hi]) {
			return nil, p.die("the comparison of %s in vim_is_xterm() carries no written length",
				cutil.PyRepr(string(text[s[0]+1:s[1]])))
		}
	}
	p.sayf("the %d literals that spell a removed name partition exactly: %d rows, 1 in "+
		"find_builtin_term() (the xterm-family special case), 1 in set_termname() (the "+
		"fallback) and %d in vim_is_xterm(), which are counted PREFIX tests -- "+
		"musl_strncasecmp(name, %s, N) -- and %s, which stays, begins with it",
		len(gone)+2+len(part["prefix"]), len(gone), len(part["prefix"]),
		cutil.PyRepr(string(text[part["prefix"][0][0]+1:part["prefix"][0][1]])),
		cutil.PyRepr(zero38Keep[0]))

	// ---- 2. what the fallback may name, computed from termcapinit() ------
	tcA, tcZ, err := defspan("termcapinit")
	if err != nil {
		return nil, err
	}
	seen := map[string]bool{}
	for _, s := range lits {
		if s[0] < tcA || s[0] >= tcZ {
			continue
		}
		v := string(text[s[0]+1 : s[1]])
		if containsStr(names, v) {
			seen[v] = true
		}
	}
	var compiled []string
	for k := range seen {
		compiled = append(compiled, k)
	}
	sort.Strings(compiled)
	if len(compiled) != 1 {
		j := strings.Join(compiled, " ")
		if j == "" {
			j = "none"
		}
		return nil, p.die("termcapinit() spells %d of builtin_terminals[] names (%s), and this phase "+
			"needs exactly one -- the name it substitutes when it is given none",
			len(compiled), j)
	}
	dflt := compiled[0]
	if !containsStr(zero38Keep, dflt) {
		return nil, p.die("termcapinit()'s compiled default is %s, which this phase deletes: the "+
			"fallback cannot be retargeted onto a row that is going", cutil.PyRepr(dflt))
	}
	fa, fz := part["fallback"][0][0], part["fallback"][0][1]
	oldFallback := string(text[fa+1 : fz])
	p.sayf("set_termname()'s no-screen fallback names %s, which goes; termcapinit()'s "+
		"compiled default is %s, which stays.  The fallback is retargeted onto it, so "+
		"after this phase there is ONE name the editor falls back to and one compiled "+
		"default, and they are the same name",
		cutil.PyRepr(oldFallback), cutil.PyRepr(dflt))

	// ---- 3. the family clause: dead by computation -----------------------
	ca, cz := part["family"][0][0], part["family"][0][1]
	if containsStr(names, oldFallback) && !containsStr(gone, oldFallback) {
		return nil, p.die("%s is still a row of builtin_terminals[], so the special case in "+
			"find_builtin_term() is live and must not be removed",
			cutil.PyRepr(string(text[ca+1:cz])))
	}
	start := bytes.LastIndexByte(text[:ca], '\n') + 1
	headEnd := ca + bytes.IndexByte(text[ca:], '\n')
	head := string(text[start:headEnd])
	if !zero38IfCall.MatchString(head) || !strings.Contains(head, "vim_is_xterm") {
		return nil, p.die("the literal %s in find_builtin_term() is not the condition of an `if` that "+
			"calls vim_is_xterm(): %s", cutil.PyRepr(string(text[ca+1:cz])), strings.TrimSpace(head))
	}
	closeParen := ca + bytes.IndexByte(text[ca:], ')')
	ob := closeParen + bytes.IndexByte(b[closeParen:], '{')
	cb := cutil.Match(b, ob)
	if cb < 0 {
		return nil, p.die("the xterm-family clause's block is not balanced")
	}
	end := cb + 1
	if end < len(text) && text[end] == '\n' {
		end++
	}
	body := text[ob+1 : cb]
	if bytes.Count(body, []byte(";")) != 1 || !bytes.Contains(body, []byte("return")) {
		return nil, p.die("the xterm-family clause does more than return a table, and this phase is "+
			"written against the clause that does: %s", strings.Join(strings.Fields(string(body)), " "))
	}
	p.sayf("the xterm-family special case in find_builtin_term() tests the ROW's name "+
		"against %s, and no row will carry that name: the clause can never fire again.  "+
		"gcc has no warning for a condition that is false at run time and no tool in "+
		"tools/sweep.sh reads one, so it is the edit's to take -- %d lines at line %d",
		cutil.PyRepr(oldFallback), bytes.Count(text[start:end], []byte{'\n'}), lineOf(start))

	// ---- 4. the message that announces the fallback ----------------------
	// The message and the name move together.  Nothing in the build checks
	// that a message tells the truth, so a retargeted fallback with the old
	// name in its text would be a lie no harness could see.
	rtA, rtZ, err := defspan("report_term_error")
	if err != nil {
		return nil, err
	}
	quoted := "'" + oldFallback + "'"
	var msgs [][2]int
	for _, s := range lits {
		if s[0] >= rtA && s[0] < rtZ && strings.Contains(string(text[s[0]+1:s[1]]), quoted) {
			msgs = append(msgs, s)
		}
	}
	if len(msgs) == 0 {
		return nil, p.die("report_term_error() does not spell %s, so this phase cannot keep its "+
			"message and its fallback in step", quoted)
	}
	p.sayf("report_term_error() spells %s in %d message(s), and each is rewritten in the "+
		"same step as the fallback itself -- nothing in the build checks that a message "+
		"tells the truth", quoted, len(msgs))

	// ---- 5. ONE PASS over the original text ------------------------------
	// Every edit below is an offset into the text as it was read.  A second
	// pass would index its spans against the first pass's output; zero phase
	// 23 measured that and left five of 437 names behind in a file that still
	// compiled.
	var edits []zero38Edit
	for _, r := range rows {
		if containsStr(gone, r.name) {
			edits = append(edits, zero38Edit{r.a, r.z, ""})
		}
	}
	edits = append(edits, zero38Edit{start, end, ""})
	edits = append(edits, zero38Edit{fa, fz + 1, `"` + dflt + `"`})
	for _, s := range msgs {
		was := string(text[s[0]+1 : s[1]])
		edits = append(edits, zero38Edit{s[0], s[1] + 1,
			`"` + strings.ReplaceAll(was, quoted, "'"+dflt+"'") + `"`})
	}
	sort.Slice(edits, func(x, y int) bool { return edits[x].a < edits[y].a })
	for k := 1; k < len(edits); k++ {
		if edits[k].a < edits[k-1].z {
			return nil, p.die("two of this phase's edits overlap at line %d, so applying them in one "+
				"pass would corrupt the file", lineOf(edits[k].a))
		}
	}
	var out []byte
	prev := 0
	for _, e := range edits {
		out = append(out, text[prev:e.a]...)
		out = append(out, e.rep...)
		prev = e.z
	}
	out = append(out, text[prev:]...)
	text = out

	// ---- 6. what the sweep is handed, computed ---------------------------
	// A `builtin_*` table whose only mention left -- literals excluded -- is
	// its own definition is dead.  The rule is what is asserted; the three
	// names it computes are printed, not required.
	var tabs []string
	for _, r := range rows {
		if !containsStr(tabs, r.tab) {
			tabs = append(tabs, r.tab)
		}
	}
	sort.Strings(tabs)
	var dead, live []string
	for _, x := range tabs {
		if zero38Mentions(text, x) == 1 {
			dead = append(dead, x)
		} else {
			live = append(live, x)
		}
	}
	if len(dead) == 0 {
		return nil, p.die("every capability table builtin_terminals[] pointed at still has a row, so " +
			"this cut orphans nothing and the sweep has nothing to find")
	}
	for _, x := range dead {
		if !regexp.MustCompile(`(?m)^static \w+ ` + regexp.QuoteMeta(x) + `\[\] = \{`).Match(text) {
			return nil, p.die("%s has one mention left and it is not its own definition", x)
		}
	}
	p.sayf("%d of the %d capability tables builtin_terminals[] pointed at have no row "+
		"left and are the sweep's: %s.  %s stay, each still pointed at -- and the "+
		"count is taken on BLANKED text, because \"builtin_xterm\" is also a string "+
		"literal and a count that read that as a reference would report a live table "+
		"dead", len(dead), len(tabs), strings.Join(dead, " "), strings.Join(live, " "))

	// ---- 7. nothing spells a removed name any more, except the prefix tests
	b2 := cutil.Blank(text)
	var q2 []int
	for _, m := range regexp.MustCompile(`"`).FindAllIndex(b2, -1) {
		q2 = append(q2, m[0])
	}
	var left [][2]int
	for k := 0; k+1 < len(q2); k += 2 {
		if containsStr(gone, string(text[q2[k]+1:q2[k+1]])) {
			left = append(left, [2]int{q2[k], q2[k+1]})
		}
	}
	lo2, hi2, ok := cutil.FindDefinition(text, b2, "vim_is_xterm")
	if !ok {
		return nil, p.die("vim_is_xterm() is not defined in this file, and the partition below is " +
			"drawn against its extent")
	}
	var stray [][2]int
	for _, s := range left {
		if !(lo2 <= s[0] && s[0] < hi2) {
			stray = append(stray, s)
		}
	}
	if len(stray) > 0 {
		var at []string
		for _, s := range stray {
			at = append(at, cutil.PyRepr(string(text[s[0]+1:s[1]])))
		}
		return nil, p.die("%d literal(s) still spell a removed terminal name outside vim_is_xterm(): "+
			"%s", len(stray), strings.Join(at, ", "))
	}
	if len(left) != len(part["prefix"]) {
		return nil, p.die("vim_is_xterm() holds %d literals spelling a removed name and held %d",
			len(left), len(part["prefix"]))
	}
	p.sayf("nothing in the output spells a removed terminal name except the %d counted "+
		"prefix test(s) in vim_is_xterm(), which is the one class this partition keeps",
		len(left))
	return text, nil
}

func containsStr(xs []string, x string) bool {
	for _, v := range xs {
		if v == x {
			return true
		}
	}
	return false
}
