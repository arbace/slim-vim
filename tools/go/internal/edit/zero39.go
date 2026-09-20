package edit

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { register("zero39", Zero39) }

var (
	z39SwitchC   = regexp.MustCompile(`\bswitch \(c\)`)
	z39Label     = regexp.MustCompile(`(?m)^[ \t]*(case .*?|default):$`)
	z39WantArg   = regexp.MustCompile(`(?m)^[ \t]*if \(want_argument\)$`)
	z39DeclWant  = regexp.MustCompile(`\n[ \t]*int +want_argument;\n`)
	z39SetWant   = regexp.MustCompile(`\n[ \t]*want_argument = FALSE;\n`)
	z39OneDflt   = regexp.MustCompile(`(?s)\A\s*\n[ \t]*default:\n(.*)\z`)
	z39ReadC     = regexp.MustCompile(`\n[ \t]*c = argv\[0\]\[argv_idx\+\+\];\n`)
	z39DeclC     = regexp.MustCompile(`\n[ \t]*int +c;\n`)
	z39DashArm   = regexp.MustCompile(`(?m)^[ \t]*else if \(argv\[0\]\[0\] == '-'\)$`)
	z39PlainElse = regexp.MustCompile(`\A\s*\n[ \t]*else\n`)
	z39EnumPair  = regexp.MustCompile(`(?m)^enum \{ (ME_\w+) = (\d+) \};$`)
	z39EnumRun   = regexp.MustCompile(`(?m)(?:^enum \{ ME_\w+ = \d+ \};\n)+`)
	z39Table     = regexp.MustCompile(`(?ms)^static char \*\(main_errors\[\]\) =\n\{\n(.*?)^\};\n`)
	z39ArgProto  = regexp.MustCompile(`(?m)^static void mainerr_arg_missing\([^)]*\);\n`)
	z39EmptyName = `^[ \t]*if \(term != nullptr && \*term == NUL\)$`
	z39GivenNone = regexp.MustCompile(`(?m)^[ \t]*if \(term == nullptr \|\| \*term == NUL\)$`)
	z39Assign    = regexp.MustCompile(`(?s)\A\s*\n[ \t]*term = (.*?);\n[ \t]*\z`)
	z39TermDecl  = regexp.MustCompile(`(?m)^([ \t]*char_u +\*term) = name;$`)
	z39TciProto  = regexp.MustCompile(`(?m)^static void termcapinit\([^)]*\);$`)
	z39Member    = regexp.MustCompile(`(?m)^[ \t]*char_u +\*term;\n`)
	z39Owner     = regexp.MustCompile(`(\w+)\s*(?:\.|->)\s*term\b`)
	z39DotTerm   = regexp.MustCompile(`(?:\.|->)\s*term\b`)
	z39SetTerm   = regexp.MustCompile(`\bset_termname\s*\(`)
	z39FnName    = regexp.MustCompile(`\n[a-zA-Z_]\w*`)
	z39Row       = regexp.MustCompile(`(?m)^[ \t]*\{\s*"([^"]*)"\s*,\s*\w+\s*\},$`)
	z39Starting  = regexp.MustCompile(`(?m)^[ \t]*starting = ([^;]+);$`)
	z39TermpNull = regexp.MustCompile(`(?m)^[ \t]*if \(termp == nullptr\)$`)
	z39NoScreen  = `^[ \t]*if \(starting != NO_SCREEN\)$`
	z39FirstLit  = regexp.MustCompile(`"([^"]*)"`)
	z39Requested = regexp.MustCompile(`\brequested\b`)
	z39TermRewr  = regexp.MustCompile(`(?m)^[ \t]*term (\+?=[^;]*);$`)
	z39Prefix    = regexp.MustCompile(`musl_strncmp\(\(char \*\)\(name\), \(char \*\)\("([^"]*)"\), \(\(usize\)(\d+)\)\)`)
	z39Needle    = regexp.MustCompile(`musl_strstr\(\(char \*\)requested, "([^"]*)"\)`)
	z39ReqDecl   = regexp.MustCompile(`\n[ \t]*char_u +\*requested = term;\n`)
)

// z39Mentions counts an IDENTIFIER with string literals excluded.
func z39Mentions(text []byte, name string) int {
	return len(regexp.MustCompile(`\b`+regexp.QuoteMeta(name)+`\b`).
		FindAll(cutil.Blank(text), -1))
}

// Zero39 removes `-T {term}`: command_line_scan() becomes one `if (argv[0][0]
// == '+')` and one `else` answering mainerr(ME_UNKNOWN_OPTION), with two
// main_errors[] rows and their enumerators, mparm_T.term, and the no-screen
// arm of set_termname() that only -T could reach.
func Zero39(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"cmdline", w}

	span := func(t []byte, name string) (int, int, error) {
		a, z, ok := cutil.FindDefinition(t, cutil.Blank(t), name)
		if !ok {
			return 0, 0, p.die("%s() is not defined in this file, and this phase is drawn against its "+
				"extent", name)
		}
		return a, z, nil
	}
	inFunction := func(t []byte, name string, edit func([]byte) ([]byte, error)) ([]byte, error) {
		a, z, err := span(t, name)
		if err != nil {
			return nil, err
		}
		seg, err := edit(t[a:z])
		if err != nil {
			return nil, err
		}
		out := append([]byte(nil), t[:a]...)
		out = append(out, seg...)
		return append(out, t[z:]...), nil
	}

	// ---- 0. the parser: the option letters, read out of the switch -------
	// Nothing is written down here.  Which letters `-` accepts is the first
	// `switch (c)` in command_line_scan(), and this phase removes every one;
	// what is left is the `default:` that was always there.
	parser := func(s []byte) ([]byte, error) {
		b := cutil.Blank(s)
		sw := z39SwitchC.FindAllIndex(s, -1)
		if len(sw) != 2 {
			return nil, p.die("command_line_scan() holds %d `switch (c)`, and this phase is written "+
				"against the two zero phase 5 left -- the letter and its argument", len(sw))
		}
		o := sw[0][0] + bytes.IndexByte(b[sw[0][0]:], '{')
		c := cutil.Match(b, o)
		if c < 0 {
			return nil, p.die("the option switch is not balanced")
		}
		body := append([]byte(nil), s[o+1:c]...)
		var labels []string
		for _, m := range z39Label.FindAllSubmatch(body, -1) {
			labels = append(labels, string(m[1]))
		}
		var letters []string
		nDefault := 0
		for _, x := range labels {
			if x == "default" {
				nDefault++
			} else {
				letters = append(letters, x)
			}
		}
		if len(letters) == 0 {
			return nil, p.die("the option switch accepts no letter at all: there is nothing here to " +
				"remove and every assertion below would be vacuous")
		}
		if nDefault != 1 || labels[len(labels)-1] != "default" {
			return nil, p.die("the option switch is %s, and this phase needs one default, last",
				cutil.PyRepr(strings.Join(labels, ", ")))
		}
		for _, lab := range letters {
			re := regexp.MustCompile(`\n[ \t]*` + regexp.QuoteMeta(lab) + `:\n(?:[^\n]*\n)*?[ \t]*break;\n`)
			n := len(re.FindAll(body, -1))
			if n != 1 {
				return nil, p.die("%s has %d arms in the shape `case: ... break;`, and this phase "+
					"removes whole arms", lab, n)
			}
			body = re.ReplaceAll(body, []byte("\n"))
		}
		out := append([]byte(nil), s[:o+1]...)
		out = append(out, body...)
		out = append(out, s[c:]...)
		s = out
		var last []string
		for _, x := range letters {
			f := strings.Fields(x)
			last = append(last, f[len(f)-1])
		}
		p.sayf("the option letters are READ OUT of the switch and not written here: %s go, "+
			"and the default that answered everything else stays", strings.Join(last, " "))

		// want_argument can no longer be TRUE, so its block cannot run.
		// What is in it is stated as a partition of the block's own text.
		m := z39WantArg.FindIndex(s)
		if m == nil {
			return nil, p.die("command_line_scan() has no `if (want_argument)` to fold")
		}
		bb := cutil.Blank(s)
		ob := m[1] + bytes.IndexByte(bb[m[1]:], '{')
		cb := cutil.Match(bb, ob)
		inside := s[ob+1 : cb]
		for _, name := range []string{"parmp->term", "ME_GARBAGE", "mainerr_arg_missing"} {
			if k := bytes.Count(inside, []byte(name)); k != 1 {
				return nil, p.die("the want_argument block names %s %d times, and this phase is "+
					"written against the one", name, k)
			}
		}
		if !bytes.Contains(inside, []byte("switch (c)")) {
			return nil, p.die("the want_argument block does not hold the argument switch, so this " +
				"phase has misread what it is deleting")
		}
		folded, err := cutil.FoldNever(s, "(?m)"+z39WantArg.String(), 1)
		if err != nil {
			return nil, p.die("the want_argument block would not fold -- %v", err)
		}
		s = folded
		s = z39DeclWant.ReplaceAll(s, []byte("\n"))
		s = z39SetWant.ReplaceAll(s, []byte("\n"))
		if z39Mentions(s, "want_argument") > 0 {
			return nil, p.die("want_argument survives the fold")
		}
		p.say("want_argument is FALSE for ever, so the block it guarded goes: the " +
			"argument switch, `parmp->term`, ME_GARBAGE and mainerr_arg_missing with it")

		// The letter switch is one `default:` now, so it IS its body.  That
		// is only a rewrite because mainerr() does not return, which is read
		// off mainerr() itself, below.
		bb = cutil.Blank(s)
		i := bytes.Index(s, []byte("switch (c)"))
		o = i + bytes.IndexByte(bb[i:], '{')
		c = cutil.Match(bb, o)
		mm := z39OneDflt.FindSubmatchIndex(s[o+1 : c])
		if mm == nil {
			return nil, p.die("the option switch did not reduce to one default label: %s",
				cutil.PyRepr(string(s[o+1:c])))
		}
		inner := s[o+1+mm[2] : o+1+mm[3]]
		k := bytes.LastIndexByte(s[:bytes.LastIndexByte(s[:i], '\n')], '\n') + 1
		end := c + bytes.IndexByte(s[c:], '\n') + 1
		ded := cutil.Dedent4(append(bytes.TrimRight(inner, " \n"), '\n'))
		out = append([]byte(nil), s[:k+1]...)
		out = append(out, ded...)
		out = append(out, s[end:]...)
		s = out
		s = z39ReadC.ReplaceAll(s, []byte("\n"))
		s = z39DeclC.ReplaceAll(s, []byte("\n"))
		if z39Mentions(s, "c") > 0 {
			return nil, p.die("`c` survives in command_line_scan()")
		}
		return s, nil
	}

	// collapse: the two arms do the same thing now, so the chain is one else.
	collapse := func(s []byte) ([]byte, error) {
		b := cutil.Blank(s)
		m := z39DashArm.FindIndex(s)
		if m == nil {
			return nil, p.die("command_line_scan() has no `-` arm left to collapse")
		}
		k := bytes.LastIndexByte(s[:m[0]], '\n') + 1
		o1 := m[1] + bytes.IndexByte(b[m[1]:], '{')
		c1 := cutil.Match(b, o1)
		nxt := z39PlainElse.FindIndex(s[c1+1:])
		if nxt == nil {
			return nil, p.die("the `-` arm is not followed by a plain else, so collapsing it would " +
				"change which branch runs")
		}
		o2 := c1 + 1 + nxt[1] + bytes.IndexByte(b[c1+1+nxt[1]:], '{')
		c2 := cutil.Match(b, o2)
		a1 := string(bytes.TrimSpace(cutil.CollapseWS(s[o1+1 : c1])))
		a2 := string(bytes.TrimSpace(cutil.CollapseWS(s[o2+1 : c2])))
		if a1 != a2 {
			return nil, p.die("the `-` arm and the last arm are not the same statement -- %s against "+
				"%s -- so they do not collapse", cutil.PyRepr(a1), cutil.PyRepr(a2))
		}
		p.sayf("a word beginning with `-` and any other word are now the same statement, "+
			"%s, so the chain is ONE else and what is kept is the else arm's own text: "+
			"the command line is `+{command}` and nothing else", a1)
		out := append([]byte(nil), s[:k+1]...)
		return append(out, s[c1+2:]...), nil
	}

	t, err := inFunction(text, "command_line_scan", parser)
	if err != nil {
		return nil, err
	}
	t, err = inFunction(t, "command_line_scan", collapse)
	if err != nil {
		return nil, err
	}

	// mainerr() is what makes dropping `c = argv[0][argv_idx++];` a rewrite
	// and not a change: it does not return.  Read off its definition.
	ma, mz, err := span(t, "mainerr")
	if err != nil {
		return nil, err
	}
	if !bytes.Contains(t[ma:mz], []byte("mch_exit(")) {
		return nil, p.die("mainerr() does not end the process, so the option arm cannot simply be its " +
			"call and the increment it dropped would have mattered")
	}

	// ---- 1. the two enumerators and the two rows -------------------------
	if k := z39Mentions(t, "mainerr_arg_missing"); k != 2 {
		return nil, p.die("mainerr_arg_missing has %d mentions after the fold, expected its "+
			"definition and its prototype", k)
	}
	t2, dropped := cutil.DeleteDefinition(t, "mainerr_arg_missing")
	if !dropped {
		return nil, p.die("mainerr_arg_missing() is not defined in this file")
	}
	t = z39ArgProto.ReplaceAll(t2, nil)
	if z39Mentions(t, "mainerr_arg_missing") > 0 {
		return nil, p.die("mainerr_arg_missing survives its own deletion")
	}

	pairs := z39EnumPair.FindAllSubmatch(t, -1)
	okOrder := len(pairs) > 0
	for k, m := range pairs {
		if v, _ := strconv.Atoi(string(m[2])); v != k {
			okOrder = false
		}
	}
	if !okOrder {
		var shown []string
		for _, m := range pairs {
			shown = append(shown, "('"+string(m[1])+"', '"+string(m[2])+"')")
		}
		return nil, p.die("the ME_* enumerators are not 0..%d in order: [%s]",
			len(pairs)-1, strings.Join(shown, ", "))
	}
	var enumNames []string
	for _, m := range pairs {
		enumNames = append(enumNames, string(m[1]))
	}
	var dead []string
	for _, n := range enumNames {
		if z39Mentions(t, n) == 1 {
			dead = append(dead, n)
		}
	}
	if len(dead) == 0 {
		return nil, p.die("no ME_* enumerator lost its last use, so this phase removed nothing the " +
			"table is indexed by and the renumbering below would be vacuous")
	}
	enumsLoc := z39EnumRun.FindIndex(t)
	tableLoc := z39Table.FindSubmatchIndex(t)
	if tableLoc == nil {
		return nil, p.die("main_errors[] is not where it was")
	}
	rowsRaw := bytes.SplitAfter(t[tableLoc[2]:tableLoc[3]], []byte{'\n'})
	var rows [][]byte
	for _, r := range rowsRaw {
		if len(r) > 0 {
			rows = append(rows, r)
		}
	}
	if len(rows) != len(pairs)+1 {
		return nil, p.die("main_errors[] has %d rows for %d enumerators; this phase only knows the "+
			"shape where the one extra row is the unreachable one whim left",
			len(rows), len(pairs))
	}
	var drop []int
	for _, n := range dead {
		drop = append(drop, indexOfStr(enumNames, n))
	}
	sort.Ints(drop)
	var keep []string
	for _, n := range enumNames {
		if !containsStr(dead, n) {
			keep = append(keep, n)
		}
	}
	var newEnum bytes.Buffer
	for k, n := range keep {
		fmt.Fprintf(&newEnum, "enum { %s = %d };\n", n, k)
	}
	var newRows bytes.Buffer
	for k, r := range rows {
		if !containsInt(drop, k) {
			newRows.Write(r)
		}
	}
	t = bytes.Replace(t, t[enumsLoc[0]:enumsLoc[1]], newEnum.Bytes(), 1)
	tableLoc = z39Table.FindSubmatchIndex(t)
	t = bytes.Replace(t, t[tableLoc[0]:tableLoc[1]],
		[]byte("static char *(main_errors[]) =\n{\n"+newRows.String()+"};\n"), 1)

	var droppedRows, renumbered []string
	for _, i := range drop {
		droppedRows = append(droppedRows, strings.TrimSpace(strings.TrimSuffix(
			strings.TrimSpace(string(rows[i])), ",")))
	}
	for k, n := range keep {
		if indexOfStr(enumNames, n) != k {
			renumbered = append(renumbered, fmt.Sprintf("%s %d->%d", n, indexOfStr(enumNames, n), k))
		}
	}
	rn := strings.Join(renumbered, ", ")
	if rn == "" {
		rn = "nothing renumbers"
	}
	p.sayf("%s lost their last use, and each takes the main_errors[] row it indexes -- %s; "+
		"%s.  The enumerator and the row are ONE thing: deadenums.py would take the "+
		"enumerator and leave the row, and the rows are positional",
		strings.Join(dead, " and "), strings.Join(droppedRows, " / "), rn)
	p.sayf("main_errors[] keeps its last row, %s, which no enumerator named before this "+
		"phase either -- whim's leftover, and pipes/zero5-edit.sh's sentence",
		strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(string(rows[len(rows)-1])), ",")))

	// ---- 2. termcapinit() takes no name ----------------------------------
	var dflt string
	tci := func(s []byte) ([]byte, error) {
		folded, err := cutil.FoldNever(s, "(?m)"+z39EmptyName, 1)
		if err != nil {
			return nil, p.die("termcapinit()'s empty-name test would not fold -- %v", err)
		}
		s = folded
		d := z39GivenNone.FindIndex(s)
		if d == nil {
			return nil, p.die("termcapinit() has no `given none` test, so the compiled default cannot " +
				"be read out of it")
		}
		b := cutil.Blank(s)
		o := d[1] + bytes.IndexByte(b[d[1]:], '{')
		c := cutil.Match(b, o)
		ass := z39Assign.FindSubmatch(s[o+1 : c])
		if ass == nil {
			return nil, p.die("the compiled default is not one assignment: %s",
				cutil.PyRepr(string(s[o+1:c])))
		}
		dflt = string(ass[1])
		end := c + bytes.IndexByte(s[c:], '\n') + 1
		k := bytes.LastIndexByte(s[:d[0]], '\n') + 1
		out := append([]byte(nil), s[:k]...)
		s = append(out, s[end:]...)

		loc := z39TermDecl.FindSubmatchIndex(s)
		if loc == nil {
			return nil, p.die("termcapinit() does not open with `char_u *term = name;`")
		}
		repl := string(s[loc[2]:loc[3]]) + " =" + dflt + ";"
		out = append([]byte(nil), s[:loc[0]]...)
		out = append(out, repl...)
		s = append(out, s[loc[1]:]...)
		s = bytes.ReplaceAll(s, []byte("termcapinit(char_u *name)"), []byte("termcapinit(void)"))
		return s, nil
	}
	t, err = inFunction(t, "termcapinit", tci)
	if err != nil {
		return nil, err
	}
	t = z39TciProto.ReplaceAll(t, []byte("static void termcapinit(void);"))
	if bytes.Count(t, []byte("termcapinit(params.term);")) != 1 {
		return nil, p.die("termcapinit() is not called with the field this phase just removed")
	}
	t = bytes.ReplaceAll(t, []byte("termcapinit(params.term);"), []byte("termcapinit();"))
	if z39Mentions(t, "name") > 0 && bytes.Contains(t, []byte("termcapinit(char_u")) {
		return nil, p.die("termcapinit() still takes a name")
	}
	p.sayf("termcapinit() takes no name -- nothing could assign the field it was handed -- "+
		"and the compiled default it substituted when it was given none, %s, is its "+
		"initialiser now.  That is pipes/zero13-edit.sh's ui_write(console) again",
		strings.TrimSpace(dflt))

	// ---- 3. mparm_T loses the field nothing assigns ----------------------
	// THE PARTITION, and it is why this is the edit's: every `.term`/`->term`
	// belongs either to this struct -- and those mentions have just gone --
	// or to another struct with a member of the same name, which is exactly
	// what deadfields.py cannot tell apart, because it matches by NAME.
	iM := bytes.Index(t, []byte("} mparm_T;"))
	if iM < 0 {
		return nil, p.die("mparm_T's definition is not balanced")
	}
	oM := cutil.RMatch(cutil.Blank(t), bytes.LastIndexByte(t[:iM+1], '}'))
	if oM < 0 {
		return nil, p.die("mparm_T's definition is not balanced")
	}
	mem := z39Member.FindIndex(t[oM:iM])
	if mem == nil {
		return nil, p.die("mparm_T has no `char_u *term;` member to remove")
	}
	out := append([]byte(nil), t[:oM+mem[0]]...)
	t = append(out, t[oM+mem[1]:]...)
	var owners []string
	for _, m := range z39Owner.FindAllSubmatch(cutil.Blank(t), -1) {
		if !containsStr(owners, string(m[1])) {
			owners = append(owners, string(m[1]))
		}
	}
	sort.Strings(owners)
	if len(owners) == 0 {
		return nil, p.die("nothing in the file names a `.term` member at all, so the partition below " +
			"says nothing -- read the file before removing this")
	}
	var mine []string
	for _, x := range owners {
		if x == "params" || x == "parmp" {
			mine = append(mine, x)
		}
	}
	if len(mine) > 0 {
		return nil, p.die("%s still names this struct's `term` field", strings.Join(mine, " "))
	}
	p.sayf("mparm_T loses its `term` member, in the EDIT: every one of the %d `.term` "+
		"mentions left belongs to another struct (%s), and deadfields.py matches by "+
		"NAME, so that tool could never see this one dead",
		len(z39DotTerm.FindAll(cutil.Blank(t), -1)), strings.Join(owners, " "))

	// ---- 4. set_termname()'s no-screen arm cannot run --------------------
	// THE ARGUMENT, computed in three parts before a line is cut.
	dA, dZ, err := span(t, "set_termname")
	if err != nil {
		return nil, err
	}
	var sites []string
	for _, m := range z39SetTerm.FindAllIndex(cutil.Blank(t), -1) {
		at := m[0]
		if dA <= at && at < dZ {
			continue
		}
		if strings.TrimSpace(string(t[bytes.LastIndexByte(t[:at], '\n')+1:at])) == "static int" {
			continue
		}
		lo := bytes.LastIndex(t[:at], []byte("\n    static "))
		who := "?"
		if lo >= 0 {
			if f := z39FnName.Find(t[lo:at]); f != nil {
				who = strings.TrimSpace(string(f))
			}
		}
		if !containsStr(sites, who) {
			sites = append(sites, who)
		}
	}
	sort.Strings(sites)
	if strings.Join(sites, "\x00") != "did_set_term\x00termcapinit" {
		j := strings.Join(sites, " ")
		if j == "" {
			j = "nowhere"
		}
		return nil, p.die("set_termname() is called from %s, and this phase is written against the "+
			"two -- termcapinit(), before there is a screen, and did_set_term(), at run "+
			"time", j)
	}
	tabStart := bytes.Index(t, []byte("static builtin_tcap_T builtin_terminals[] = {"))
	tabEnd := tabStart + bytes.Index(t[tabStart:], []byte("\n};"))
	var tabRows []string
	for _, m := range z39Row.FindAllSubmatch(t[tabStart:tabEnd], -1) {
		tabRows = append(tabRows, string(m[1]))
	}
	dn := z39FirstLit.FindStringSubmatch(dflt)
	if dn == nil || !containsStr(tabRows, dn[1]) {
		name := ""
		if dn != nil {
			name = dn[1]
		}
		return nil, p.die("the compiled default %s is not a row of builtin_terminals[], so "+
			"termcapinit() can still be refused and the arm below is live", cutil.PyRepr(name))
	}
	defaultName := dn[1]
	var assigns []string
	for _, m := range z39Starting.FindAllSubmatch(t, -1) {
		v := strings.TrimSpace(string(m[1]))
		if !containsStr(assigns, v) {
			assigns = append(assigns, v)
		}
	}
	sort.Strings(assigns)
	if containsStr(assigns, "NO_SCREEN") {
		return nil, p.die("something assigns starting = NO_SCREEN, so `starting != NO_SCREEN` is not "+
			"true wherever the arm below is reached: %s", strings.Join(assigns, " "))
	}
	p.sayf("set_termname() is called from %s and from nowhere else; termcapinit() now "+
		"passes %s, which IS a row of builtin_terminals[]; and the only assignments to "+
		"`starting` are %s -- so a refusal can only come from did_set_term(), where "+
		"`starting != NO_SCREEN`",
		strings.Join(sites, " and "), cutil.PyRepr(defaultName), strings.Join(assigns, " and "))

	var tail string
	stn := func(s []byte) ([]byte, error) {
		b := cutil.Blank(s)
		m := z39TermpNull.FindIndex(s)
		if m == nil {
			return nil, p.die("set_termname() has no `termp == nullptr` arm")
		}
		o := m[1] + bytes.IndexByte(b[m[1]:], '{')
		c := cutil.Match(b, o)
		if c < 0 {
			return nil, p.die("the refusal arm is not balanced")
		}
		pad := s[bytes.LastIndexByte(s[:c], '\n')+1 : c]
		inner, err := cutil.FoldAlways(s[o+1:c], "(?m)"+z39NoScreen, 1)
		if err != nil {
			return nil, p.die("the no-screen test would not fold -- %v", err)
		}
		k := bytes.Index(inner, []byte("return FAIL;\n")) + len("return FAIL;\n")
		tail = string(inner[k:])
		if strings.TrimSpace(tail) == "" {
			return nil, p.die("nothing follows the refusal, so this phase has already been applied or " +
				"the arm is not the one it was written against")
		}
		out := append([]byte(nil), s[:o+1]...)
		out = append(out, inner[:k]...)
		out = append(out, pad...)
		return append(out, s[c:]...), nil
	}
	sA, sZ, err := span(t, "set_termname")
	if err != nil {
		return nil, err
	}
	seg, err := stn(t[sA:sZ])
	if err != nil {
		return nil, err
	}
	out = append([]byte(nil), t[:sA]...)
	out = append(out, seg...)
	t = append(out, t[sZ:]...)
	p.sayf("the no-screen test folds ALWAYS, and what followed the refusal is unreachable "+
		"and goes: %s", strings.Join(strings.Fields(tail), " "))

	// The name the fallback promised, read out of the text just deleted.
	nm := z39FirstLit.FindStringSubmatch(tail)
	if nm == nil || !containsStr(tabRows, nm[1]) {
		return nil, p.die("the deleted fallback does not name a row of builtin_terminals[], so the " +
			"message below cannot be kept in step with it")
	}
	promised := nm[1]
	if !strings.Contains(tail, "report_default_term") {
		return nil, p.die("the deleted text does not call report_default_term(), which this phase " +
			"leaves for the sweep -- read the arm before removing this")
	}

	message := func(s []byte) ([]byte, error) {
		re := regexp.MustCompile(`,[^"]*'` + regexp.QuoteMeta(promised) + `'`)
		o := re.ReplaceAll(s, nil)
		if bytes.Equal(o, s) {
			return nil, p.die("report_term_error() does not promise %s, so there is nothing here to "+
				"keep in step with the fallback", cutil.PyRepr(promised))
		}
		var left []string
		for _, x := range tabRows {
			if bytes.Contains(o, []byte("'"+x+"'")) {
				left = append(left, x)
			}
		}
		if len(left) > 0 {
			return nil, p.die("report_term_error() still names %s after the cut", strings.Join(left, " "))
		}
		return o, nil
	}
	t, err = inFunction(t, "report_term_error", message)
	if err != nil {
		return nil, err
	}
	p.sayf("report_term_error() stops promising %s: phase 38 moved the message and the "+
		"fallback together because nothing in the build checks that a message tells the "+
		"truth, and this is that rule with no fallback left to name", cutil.PyRepr(promised))

	// ---- 5. `requested` is `term` for the one test that reads it ---------
	requested := func(s []byte) ([]byte, error) {
		if k := len(z39Requested.FindAll(cutil.Blank(s), -1)); k != 2 {
			return nil, p.die("`requested` has %d mentions in set_termname(), and this phase is "+
				"written against two -- its declaration and the 256-colour test", k)
		}
		var rew []string
		for _, m := range z39TermRewr.FindAllSubmatch(s, -1) {
			v := strings.TrimSpace(string(m[1]))
			if !containsStr(rew, v) {
				rew = append(rew, v)
			}
		}
		sort.Strings(rew)
		if strings.Join(rew, "\x00") != "+= 8" {
			j := strings.Join(rew, " / ")
			if j == "" {
				j = "nothing"
			}
			return nil, p.die("`term` is rewritten as %s inside set_termname(), and `requested` can "+
				"only be folded into it while the prefix strip is the only one", j)
		}
		bA, bZ, err := span(t, "term_is_builtin")
		if err != nil {
			return nil, err
		}
		pre := z39Prefix.FindSubmatch(t[bA:bZ])
		if pre == nil {
			return nil, p.die("term_is_builtin() does not strip a counted literal prefix, so what " +
				"`term += 8` skips cannot be read off the file")
		}
		if n, _ := strconv.Atoi(string(pre[2])); len(pre[1]) != n {
			return nil, p.die("term_is_builtin() does not strip a counted literal prefix, so what " +
				"`term += 8` skips cannot be read off the file")
		}
		nd := z39Needle.FindSubmatch(s)
		if nd == nil {
			return nil, p.die("the 256-colour test is not a musl_strstr on `requested`")
		}
		if bytes.IndexByte(pre[1], nd[1][0]) >= 0 {
			return nil, p.die("%s begins with a character the stripped prefix %s contains, so a match "+
				"could start inside the prefix and `requested` is NOT `term` here",
				cutil.PyRepr(string(nd[1])), cutil.PyRepr(string(pre[1])))
		}
		s = bytes.ReplaceAll(s,
			[]byte(`musl_strstr((char *)requested, "`+string(nd[1])+`")`),
			[]byte(`musl_strstr((char *)term, "`+string(nd[1])+`")`))
		before := len(s)
		s = z39ReqDecl.ReplaceAll(s, []byte("\n"))
		if len(s) == before {
			return nil, p.die("`requested` is not declared as `= term`")
		}
		p.sayf("`requested` goes: it existed because the fallback reassigned `term`, and "+
			"the only rewrite left is the %s that strips %s -- %s cannot match inside "+
			"that, because it begins with a character the prefix does not hold",
			rew[0], cutil.PyRepr(string(pre[1])), cutil.PyRepr(string(nd[1])))
		return s, nil
	}
	rA, rZ, err := span(t, "set_termname")
	if err != nil {
		return nil, err
	}
	seg, err = requested(t[rA:rZ])
	if err != nil {
		return nil, err
	}
	out = append([]byte(nil), t[:rA]...)
	out = append(out, seg...)
	t = append(out, t[rZ:]...)

	// ---- 6. what is left, as a partition ---------------------------------
	goneNames := []string{"want_argument", "mainerr_arg_missing", "ME_GARBAGE",
		"ME_ARG_MISSING", "requested"}
	for _, name := range goneNames {
		if k := z39Mentions(t, name); k != 0 {
			return nil, p.die("%s still has %d mentions", name, k)
		}
	}
	for _, name := range []string{"ME_UNKNOWN_OPTION", "ME_EXTRA_CMD", "MAX_ARG_CMDS",
		"exe_commands", "p_paste", "did_set_term", "report_term_error"} {
		if z39Mentions(t, name) == 0 {
			return nil, p.die("%s went, and it is not this phase's", name)
		}
	}
	if k := z39Mentions(t, "report_default_term"); k != 1 {
		return nil, p.die("report_default_term has %d mentions, and this phase leaves it at one -- "+
			"its own definition, which is what the sweep takes", k)
	}
	p.sayf("0 mentions of %s; report_default_term is down to its definition and is the "+
		"sweep's; ME_UNKNOWN_OPTION, ME_EXTRA_CMD, MAX_ARG_CMDS, exe_commands and "+
		"'paste' are untouched", strings.Join(goneNames, ", "))
	return t, nil
}

func indexOfStr(xs []string, x string) int {
	for i, v := range xs {
		if v == x {
			return i
		}
	}
	return -1
}

func containsInt(xs []int, x int) bool {
	for _, v := range xs {
		if v == x {
			return true
		}
	}
	return false
}
