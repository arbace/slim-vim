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
	"time"

	"slimvim.local/tools/internal/cutil"
	"slimvim.local/tools/internal/harness"
)

func init() { register("zero38", Zero38) }

var (
	z38Row      = regexp.MustCompile(`(?m)^[ \t]*\{\s*"([^"]*)"\s*,\s*(\w+)\s*\},\n`)
	z38Quote    = regexp.MustCompile(`"`)
	z38VimErr   = regexp.MustCompile(`\bE\d+:`)
	z38ErrWord  = regexp.MustCompile(`\bE\d+\b`)
	z38ErrTok   = regexp.MustCompile(`^E\d+$`)
	z38Stream   = regexp.MustCompile(`stream (\d+)`)
	z38Counted  = regexp.MustCompile(`^[\s)]*,\s*\(\d+\)`)
	z38Prefix   = regexp.MustCompile(`musl_strncasecmp\(\(char \*\)\(name\), \(char \*\)\("([^"]*)"\), \((\d+)\)\)\s*(==|!=)`)
	z38IfaceWrn = regexp.MustCompile(`warning: '([a-zA-Z_][a-zA-Z_0-9]*)' used but never defined`)
	z38Inc      = regexp.MustCompile(`^ *# *include `)
)

type z38R struct{ name, tab, text string }

func z38Table(t string) (int, int, []z38R, bool) {
	i := strings.Index(t, "static builtin_tcap_T builtin_terminals[] = {")
	if i < 0 {
		return 0, 0, nil, false
	}
	j := strings.Index(t[i:], "\n};")
	if j < 0 {
		return 0, 0, nil, false
	}
	j += i
	var rows []z38R
	for _, m := range z38Row.FindAllStringSubmatch(t[i:j], -1) {
		rows = append(rows, z38R{m[1], m[2], m[0]})
	}
	return i, j, rows, true
}

func z38Def(t, b, name string) (int, int, bool) {
	return cutil.FindDefinition([]byte(t), []byte(b), name)
}

// z38Lits is the heredoc's literals(): the blanked text and the spans of its
// string delimiters, in pairs.
func z38Lits(t string) (string, [][2]int, bool) {
	b := string(cutil.Blank([]byte(t)))
	q := z38Quote.FindAllStringIndex(b, -1)
	if len(q)%2 != 0 {
		return b, nil, false
	}
	var out [][2]int
	for k := 0; k < len(q); k += 2 {
		out = append(out, [2]int{q[k][0], q[k+1][0]})
	}
	return b, out, true
}

func z38Names(rows []z38R) []string {
	var out []string
	for _, r := range rows {
		out = append(out, r.name)
	}
	return out
}

// z38Blocks is the heredoc's blocks(): a record file split at `=== ` heads,
// keys in insertion order.
func z38Blocks(p string) ([]string, map[string]string) {
	var order []string
	out := map[string]string{}
	cur, have := "", false
	for _, line := range strings.SplitAfter(readFile(p), "\n") {
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, "=== ") {
			cur = strings.TrimSpace(line)[4:]
			if _, ok := out[cur]; !ok {
				order = append(order, cur)
			}
			out[cur] = ""
			have = true
		} else if have {
			out[cur] += line
		}
	}
	return order, out
}

// Zero38 is phase 38's check: the eight terminal names.
func Zero38(w io.Writer, args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: check zero38 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	f := filepath.Join(work, "zero-vim.c")
	oldC := filepath.Join(state, "old.c")
	r := &rep{tag: "terms", w: w}
	stop := func(format string, a ...any) error {
		r.say(format, a...)
		return harness.ErrReported
	}
	fileLines := func(p string) []string {
		s := strings.TrimRight(readFile(p), "\n")
		if s == "" {
			return nil
		}
		return strings.Split(s, "\n")
	}
	beforeRaw := strings.TrimRight(readFile(filepath.Join(state, "input-lines")), "\n")
	tmp, err := os.MkdirTemp("", "zero38-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	T := func(n string) string { return filepath.Join(tmp, n) }
	mk := readFile(filepath.Join(work, "Makefile"))
	cflagsS, ldflagsS := "", ""
	if m := z29CFlags.FindStringSubmatch(mk); m != nil {
		cflagsS = m[1]
	}
	if m := z29LDFlags.FindStringSubmatch(mk); m != nil {
		ldflagsS = m[1]
	}

	// THE PRODUCT, REBUILT, and the clean is checked rather than trusted.
	_ = exec.Command("make", "-C", work, "clean").Run()
	newBin := filepath.Join(work, "zero-vim")
	if _, e := os.Stat(newBin); e == nil {
		(&rep{tag: "build", w: w}).say("the clean did not remove zero-vim, so nothing below would be a recording of this phase")
		return harness.ErrReported
	}
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		(&rep{tag: "build", w: w}).say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}

	// --- the controls, written first and built in parallel --------------------------
	// tools/cutil.py -- named as a PATH so tools/implhash.sh hashes it into
	// this phase's key.  Do not delete it.
	newT, oldT := readFile(f), readFile(oldC)
	_, _, orows, ok1 := z38Table(oldT)
	iN, jN, nrows, ok2 := z38Table(newT)
	if !ok1 || !ok2 {
		return stop("builtin_terminals[] is not in one of the two texts")
	}
	nnames := z38Names(nrows)
	var GONE []string
	for _, x := range orows {
		if !contains(nnames, x.name) {
			GONE = append(GONE, x.name)
		}
	}
	if len(GONE) == 0 {
		return stop("the output keeps every row the input had: there is nothing to check")
	}
	bNew := string(cutil.Blank([]byte(newT)))
	bOld := string(cutil.Blank([]byte(oldT)))
	lo, hi, _ := z38Def(newT, bNew, "set_termname")
	seg := newT[lo:hi]
	fbSet := map[string]bool{}
	for _, x := range nrows {
		if strings.Contains(seg, `"`+x.name+`"`) {
			fbSet[x.name] = true
		}
	}
	if len(fbSet) != 1 {
		return stop("set_termname() names %d of the surviving rows and this check needs one -- "+
			"the fallback", len(fbSet))
	}
	NEWFB := z27Keys(fbSet)[0]
	olo, ohi, _ := z38Def(oldT, bOld, "set_termname")
	ofb := map[string]bool{}
	for _, n := range GONE {
		if strings.Contains(oldT[olo:ohi], `"`+n+`"`) {
			ofb[n] = true
		}
	}
	if len(ofb) != 1 {
		return stop("set_termname() in the INPUT names %d removed rows and this check needs one", len(ofb))
	}
	OLDFB := z27Keys(ofb)[0]
	c1 := newT[:lo] + strings.ReplaceAll(seg, `"`+NEWFB+`"`, `"`+OLDFB+`"`) + newT[hi:]
	b1 := string(cutil.Blank([]byte(c1)))
	lo, hi, _ = z38Def(c1, b1, "report_term_error")
	c1 = c1[:lo] + strings.ReplaceAll(c1[lo:hi], "'"+NEWFB+"'", "'"+OLDFB+"'") + c1[hi:]
	if c1 == newT {
		return stop("the repair-left-out control changed nothing, so it is not a control")
	}
	os.WriteFile(T("c1.c"), []byte(c1), 0o644)
	_, olits, _ := z38Lits(oldT)
	flo, fhi, _ := z38Def(oldT, bOld, "find_builtin_term")
	var hits [][2]int
	for _, l := range olits {
		if flo <= l[0] && l[0] < fhi && contains(GONE, oldT[l[0]+1:l[1]]) {
			hits = append(hits, l)
		}
	}
	if len(hits) != 1 {
		return stop("find_builtin_term() in the input spells %d removed names, and this check is "+
			"written against one -- the xterm-family special case", len(hits))
	}
	a := hits[0][0]
	start := strings.LastIndex(oldT[:a], "\n") + 1
	ob := strings.Index(bOld[strings.Index(oldT[a:], ")")+a:], "{") + strings.Index(oldT[a:], ")") + a
	cb := cutil.Match([]byte(bOld), ob)
	end := cb + 1
	if end < len(oldT) && oldT[end] == '\n' {
		end++
	}
	clause := oldT[start:end]
	nlo, nhi, _ := z38Def(newT, bNew, "find_builtin_term")
	if oldT[flo:start]+oldT[end:fhi] != newT[nlo:nhi] {
		return stop("the input's find_builtin_term() minus the xterm-family clause is NOT the " +
			"output's, so this phase did something else to that function as well")
	}
	c2 := newT[:nlo] + oldT[flo:start] + clause + oldT[end:fhi] + newT[nhi:]
	os.WriteFile(T("c2.c"), []byte(c2), 0o644)
	os.WriteFile(T("clause"), []byte(clause), 0o644)
	const MARK = "XTERMFAMILY"
	ins := strings.Replace(clause, "        {\n", "        {\n            host_message(\""+MARK+"\\n\", -1, TRUE);\n", 1)
	if ins == clause {
		return stop("the xterm-family clause does not open with a braced block on its own line, " +
			"so the marker cannot be put inside it")
	}
	for _, x := range []struct{ name, text string }{{"i-old", oldT}, {"i-new", c2}} {
		if strings.Count(x.text, clause) != 1 {
			return stop("the clause is not in %s exactly once, so the instrumented build would "+
				"not be one", x.name)
		}
		os.WriteFile(T(x.name+".c"), []byte(strings.ReplaceAll(x.text, clause, ins)), 0o644)
	}
	last := nrows[len(nrows)-1]
	if strings.Count(newT, last.text) != 1 {
		return stop("the last row of the output table is not one line of the file")
	}
	os.WriteFile(T("c3.c"), []byte(strings.ReplaceAll(newT, last.text, "")), 0o644)
	c3Name := last.name
	back, tab := GONE[0], nrows[0].tab
	row := fmt.Sprintf("    {\"%s\", %s},\n", back, tab)
	c4 := newT[:iN] + strings.Replace(newT[iN:jN], nrows[0].text, row+nrows[0].text, 1) + newT[jN:]
	if c4 == newT {
		return stop("the put-back control changed nothing, so it is not a control")
	}
	os.WriteFile(T("c4.c"), []byte(c4), 0o644)
	c4Name := back

	var wgB sync.WaitGroup
	for _, v := range []string{"c1", "c2", "c3", "c4", "i-old", "i-new"} {
		v := v
		wgB.Add(1)
		go func() {
			defer wgB.Done()
			a := append(append(strings.Fields(cflagsS), strings.Fields(ldflagsS)...), "-o", T(v), T(v+".c"))
			c := exec.Command("gcc", a...)
			c.Env = append(os.Environ(), "SOURCE_DATE_EPOCH=0")
			c.Stdout, c.Stderr = w, w
			c.Run()
		}()
	}
	defer wgB.Wait()

	// --- 1. THE CUT, computed from the input -------------------------------------------
	onames := z38Names(orows)
	var extra []string
	for _, n := range nnames {
		if !contains(onames, n) {
			extra = append(extra, n)
		}
	}
	if len(extra) > 0 {
		return stop("the output names a terminal the input did not: %s -- this phase removes "+
			"rows and adds none", strings.Join(extra, " "))
	}
	// The section-1 heredoc asks this again in its own words.  Unreachable
	// here -- the controls above already refused on an empty GONE -- and kept
	// so that reordering the two cannot drop the question.
	if len(GONE) == 0 {
		return stop("the output keeps every row, so every assertion below is vacuous")
	}
	if len(nnames) < 2 {
		return stop("the output keeps %d rows, and an editor with fewer than two terminals it "+
			"can name is not what this phase is", len(nnames))
	}
	for _, x := range nrows {
		var was z38R
		for _, o := range orows {
			if o.name == x.name {
				was = o
				break
			}
		}
		if x.text != was.text {
			return stop("the row for %s is not the row it was: %s became %s", pyRepr26(x.name),
				pyRepr26(strings.TrimSpace(was.text)), pyRepr26(strings.TrimSpace(x.text)))
		}
	}
	r.say("builtin_terminals[] %d rows -> %d: %s go, %s stay, and each of the two that "+
		"stay is byte for byte the row it was -- a phase that repointed one at another "+
		"table would pass a count and fail here", len(orows), len(nrows), strings.Join(GONE, " "), strings.Join(nnames, " "))
	mentions := func(b, name string) int {
		return len(regexp.MustCompile(`\b` + name + `\b`).FindAllStringIndex(b, -1))
	}
	tabSet := map[string]bool{}
	for _, x := range orows {
		tabSet[x.tab] = true
	}
	tabs := z27Keys(tabSet)
	var pred, live []string
	for _, x := range tabs {
		kept := false
		for _, o := range orows {
			if o.tab == x && contains(nnames, o.name) {
				kept = true
			}
		}
		if kept {
			live = append(live, x)
		} else {
			pred = append(pred, x)
		}
	}
	if len(pred) == 0 {
		return stop("every capability table the input pointed at still has a row, so this cut " +
			"orphans nothing and the sweep had nothing to find")
	}
	var bad []string
	for _, x := range pred {
		if n := mentions(bNew, x); n > 0 {
			bad = append(bad, fmt.Sprintf("%s survives with %d mention(s) and has no row left", x, n))
		}
	}
	for _, x := range live {
		if n := mentions(bNew, x); n < 2 {
			bad = append(bad, fmt.Sprintf("%s still has a row and has %d mention(s) left", x, n))
		}
	}
	if len(bad) > 0 {
		return stop("the capability tables did not go as the rows say they must:\n  %s", strings.Join(bad, "\n  "))
	}
	r.say("%d of the %d capability tables the input pointed at have no row left and the "+
		"sweep took every one -- %s; %s stay, each still pointed at.  The set is "+
		"computed from the rows, on text whose string literals are blanked, because "+
		"\"builtin_xterm\" is a literal and not a reference",
		len(pred), len(tabs), strings.Join(pred, " "), strings.Join(live, " "))
	var before int
	fmt.Sscanf(strings.TrimSpace(beforeRaw), "%d", &before)
	after := strings.Count(newT, "\n")
	if !strings.HasSuffix(newT, "\n") {
		after++
	}
	if after >= before {
		return stop("the file did not shrink: %d -> %d", before, after)
	}
	r.say("the file lost %d lines, %d -> %d: the %d rows, the xterm-family clause, and "+
		"the %d capability tables the sweep found under them", before-after, before, after, len(GONE), len(pred))

	// --- 2. THE PARTITION ------------------------------------------------------------------
	if _, _, ok := z38Lits(oldT); !ok {
		return stop("a text has an odd number of string delimiters after blanking")
	}
	i := strings.Index(oldT, "static builtin_tcap_T builtin_terminals[] = {")
	j := strings.Index(oldT[i:], "\n};") + i
	type cls struct {
		kind   string
		lo, hi int
	}
	fl, fh, _ := z38Def(oldT, bOld, "find_builtin_term")
	sl, sh, _ := z38Def(oldT, bOld, "set_termname")
	vl, vh, _ := z38Def(oldT, bOld, "vim_is_xterm")
	CLASS := []cls{{"row", i, j}, {"family", fl, fh}, {"fallback", sl, sh}, {"prefix", vl, vh}}
	part := map[string]int{}
	var loose []string
	for _, l := range olits {
		s := oldT[l[0]+1 : l[1]]
		if !contains(GONE, s) {
			continue
		}
		placed := false
		for _, c := range CLASS {
			if c.lo <= l[0] && l[0] < c.hi {
				part[c.kind]++
				placed = true
				break
			}
		}
		if !placed {
			loose = append(loose, s)
		}
	}
	if len(loose) > 0 {
		set := map[string]bool{}
		for _, x := range loose {
			set[x] = true
		}
		return stop("the input spells a removed terminal name in a place this phase has no "+
			"class for: %s", strings.Join(z27Keys(set), " "))
	}
	if part["row"] != len(GONE) || part["family"] != 1 || part["fallback"] != 1 {
		return stop("the input partitions as {'row': %d, 'family': %d, 'fallback': %d, 'prefix': %d}, and this "+
			"phase is written against one row per removed name, one family clause and one fallback",
			part["row"], part["family"], part["fallback"], part["prefix"])
	}
	bn, nlits, ok := z38Lits(newT)
	if !ok {
		return stop("a text has an odd number of string delimiters after blanking")
	}
	lo, hi, _ = z38Def(newT, bn, "vim_is_xterm")
	var left [][2]int
	for _, l := range nlits {
		if contains(GONE, newT[l[0]+1:l[1]]) {
			left = append(left, l)
		}
	}
	straySet := map[string]bool{}
	for _, l := range left {
		if !(lo <= l[0] && l[0] < hi) {
			straySet[newT[l[0]+1:l[1]]] = true
		}
	}
	if len(straySet) > 0 {
		return stop("the output still spells a removed terminal name outside vim_is_xterm(): %s",
			strings.Join(z27Keys(straySet), " "))
	}
	if len(left) != part["prefix"] {
		return stop("vim_is_xterm() spells a removed name %d times in the output and %d in the "+
			"input", len(left), part["prefix"])
	}
	leftSet := map[string]bool{}
	for _, l := range left {
		a, z := l[0], l[1]
		from := a - 80
		if from < 0 {
			from = 0
		}
		to := z + 16
		if to > len(newT) {
			to = len(newT)
		}
		if !strings.Contains(newT[from:a], "musl_strncasecmp") || !z38Counted.MatchString(newT[z+1:to]) {
			return stop("%s survives in vim_is_xterm() other than as a counted prefix test", pyRepr26(newT[a+1:z]))
		}
		leftSet[newT[a+1:z]] = true
	}
	r.say("the %d literals that spell a removed name in the input partition %d rows / 1 "+
		"family clause / 1 fallback / %d prefix tests, and the output keeps ONLY the "+
		"last class: %s in vim_is_xterm(), each a musl_strncasecmp with its length "+
		"written out, and %s -- which stays -- begins with it",
		part["row"]+part["family"]+part["fallback"]+part["prefix"], part["row"], part["prefix"],
		strings.Join(z27Keys(leftSet), " "), pyRepr26(nnames[0]))

	// --- 3. THE FALLBACK NAMES A ROW THAT EXISTS ----------------------------------------
	named := map[string]string{}
	for _, fn := range []string{"set_termname", "termcapinit"} {
		lo, hi, _ := z38Def(newT, bn, fn)
		got := map[string]bool{}
		for _, l := range nlits {
			s := newT[l[0]+1 : l[1]]
			if lo <= l[0] && l[0] < hi && contains(onames, s) {
				got[s] = true
			}
		}
		gs := z27Keys(got)
		if len(gs) != 1 {
			g := strings.Join(gs, " ")
			if g == "" {
				g = "none"
			}
			return stop("%s() names %d terminals of the input table (%s) and this check needs "+
				"exactly one", fn, len(gs), g)
		}
		if !contains(nnames, gs[0]) {
			return stop("%s() names %s, which this phase removed: a name written outside the "+
				"table must be a row the table still has", fn, pyRepr26(gs[0]))
		}
		named[fn] = gs[0]
	}
	if named["set_termname"] != named["termcapinit"] {
		return stop("set_termname()'s fallback is %s and termcapinit()'s compiled default is "+
			"%s: after this phase they must be the same name", pyRepr26(named["set_termname"]), pyRepr26(named["termcapinit"]))
	}
	lo, hi, _ = z38Def(newT, bn, "report_term_error")
	var msgs []string
	for _, l := range nlits {
		if lo <= l[0] && l[0] < hi {
			msgs = append(msgs, newT[l[0]+1:l[1]])
		}
	}
	quoted := "'" + named["set_termname"] + "'"
	foundQ, foundGone := false, false
	for _, m := range msgs {
		if strings.Contains(m, quoted) {
			foundQ = true
		}
		for _, g := range GONE {
			if strings.Contains(m, "'"+g+"'") {
				foundGone = true
			}
		}
	}
	if !foundQ {
		return stop("report_term_error() does not name %s, so the message and the fallback "+
			"disagree and nothing in the build would say so", quoted)
	}
	if foundGone {
		return stop("report_term_error() still names a removed terminal")
	}
	r.say("set_termname()'s fallback, termcapinit()'s compiled default and "+
		"report_term_error()'s message all name %s, which is a row the table still has: "+
		"after this phase there is ONE name the editor falls back to", pyRepr26(named["set_termname"]))
	r.say("the cut: %d rows, one dead clause and %d tables, and one repair", len(GONE), len(pred))

	wgB.Wait()

	// --- 4. THE FALLBACK'S CONTROL: the repair left out ---------------------------------
	rec := func(bin, src, out string) error {
		c := exec.Command("sh", "tools/zrecord.sh", bin, src, T(out))
		c.Stderr = w
		return c.Run()
	}
	if err := rec(newBin, f, "rec-new"); err != nil {
		return harness.ErrReported
	}
	var wgR sync.WaitGroup
	for _, x := range [][3]string{
		{T("c1"), T("c1.c"), "rec-c1"}, {T("c2"), T("c2.c"), "rec-c2"},
		{T("i-old"), T("i-old.c"), "rec-i-old"}, {T("i-new"), T("i-new.c"), "rec-i-new"},
	} {
		x := x
		wgR.Add(1)
		go func() { defer wgR.Done(); rec(x[0], x[1], x[2]) }()
	}
	wgR.Wait()
	rf := &rep{tag: "fallback", w: w}
	type mv struct{ k, a, b string }
	var moved []mv
	fbFail := func() error {
		for _, what := range []string{"ref-excmds.txt", "ref-argv.txt", "ref-pty.txt", "ref-term.txt"} {
			a, b := filepath.Join(T("rec-new"), what), filepath.Join(T("rec-c1"), what)
			if what == "ref-term.txt" {
				if readFile(a) != readFile(b) {
					return fmt.Errorf("the repair-left-out control moved the TERMINAL table, which " +
						"the fallback has nothing to do with")
				}
				continue
			}
			order, x := z38Blocks(a)
			_, y := z38Blocks(b)
			for _, k := range order {
				if yv, ok := y[k]; !ok || x[k] != yv {
					moved = append(moved, mv{k, x[k], y[k]})
				}
			}
		}
		ents, _ := os.ReadDir(filepath.Join(T("rec-new"), "screen"))
		var sa []string
		for _, e := range ents {
			sa = append(sa, e.Name())
		}
		sort.Strings(sa)
		for _, c := range sa {
			if readFile(filepath.Join(T("rec-new"), "screen", c)) != readFile(filepath.Join(T("rec-c1"), "screen", c)) {
				moved = append(moved, mv{"case:" + c, "", ""})
			}
		}
		if len(moved) == 0 {
			return fmt.Errorf("the repair-left-out control moved NOTHING, so the fallback repair is " +
				"not load-bearing and this phase should not have made it")
		}
		allT := true
		var ks []string
		for _, m := range moved {
			ks = append(ks, m.k)
			if !strings.HasPrefix(m.k, "-T ") {
				allT = false
			}
		}
		if !allT {
			return fmt.Errorf("the repair-left-out control moved records that do not name a terminal "+
				"on the command line: %s", strings.Join(ks, " "))
		}
		for _, m := range moved {
			if strings.Contains(m.a, "E437") || !strings.Contains(m.b, "E437") {
				return fmt.Errorf("%s does not go from drawing to E437 when the repair is left out", pyRepr26(m.k))
			}
			fa := z38Stream.FindStringSubmatch(m.a)
			fbm := z38Stream.FindStringSubmatch(m.b)
			var na, nb int
			if fa != nil {
				fmt.Sscanf(fa[1], "%d", &na)
			}
			if fbm != nil {
				fmt.Sscanf(fbm[1], "%d", &nb)
			}
			if fa == nil || fbm == nil || nb >= na {
				return fmt.Errorf("%s draws no less with the repair left out", pyRepr26(m.k))
			}
		}
		return nil
	}
	if err := fbFail(); err != nil {
		rf.say("%s", err.Error())
		return harness.ErrReported
	}
	var kr []string
	for _, m := range moved {
		kr = append(kr, pyRepr26(m.k))
	}
	rf.say("the repair is load-bearing: with the fallback left naming %s, %d record(s) "+
		"move -- %s -- each from drawing %s bytes to %s bytes and E437: Terminal "+
		"capability \"cm\" required.  The repair points it at %s instead, and those "+
		"records are the baseline's again", pyRepr26(OLDFB), len(moved), strings.Join(kr, ", "),
		z38Stream.FindStringSubmatch(moved[0].a)[1], z38Stream.FindStringSubmatch(moved[0].b)[1], pyRepr26(NEWFB))

	// --- 5. THE CLAUSE IS DEAD, TWICE -----------------------------------------------------
	rc := &rep{tag: "clause", w: w}
	if dl := diffRQ(T("rec-c2"), T("rec-new")); len(dl) > 0 {
		rc.say("the output with the xterm-family clause RESTORED records something different, so removing it was not neutral:")
		for k, l := range dl {
			if k >= 10 {
				break
			}
			fmt.Fprintf(w, "               %s\n", l)
		}
		return harness.ErrReported
	}
	countMarked := func(dir string) int {
		ents, _ := os.ReadDir(dir)
		n := 0
		for _, e := range ents {
			if strings.Contains(readFile(filepath.Join(dir, e.Name())), "XTERMFAMILY") {
				n++
			}
		}
		return n
	}
	hitOld := countMarked(filepath.Join(T("rec-i-old"), "screen"))
	hitNew := countMarked(filepath.Join(T("rec-i-new"), "screen"))
	se, _ := os.ReadDir(filepath.Join(T("rec-new"), "screen"))
	cases := len(se)
	if hitOld != cases || hitNew != 0 {
		rc.say("the instrumented pair does not say what this phase claims: the INPUT entered the clause in %d "+
			"of %d screen records and the OUTPUT in %d, where %d and 0 were due", hitOld, cases, hitNew, cases)
		return harness.ErrReported
	}
	rc.say("the xterm-family clause is dead TWICE OVER: the output with it RESTORED records byte for byte what "+
		"the output records, over %d screen cases and every command row; and the identical marker inside it, "+
		"reached through host_message(), is in %d of %d screen records on the INPUT and %d on the output",
		cases, hitOld, cases, hitNew)
	rc.say("-- which is the finding a reader would not predict: the compiled default is %s, the removed row "+
		"sorted BEFORE it, and vim_is_xterm() answers yes to it, so EVERY startup of the input resolved through "+
		"the family clause and the surviving row was never reached.  After this phase it is, and it gives the "+
		"same table", NEWFB)

	// --- 6. THE TABLE, before and after -------------------------------------------------
	oldBin, _ := filepath.Abs(filepath.Join(state, "old"))
	var wgT sync.WaitGroup
	for _, x := range [][2]string{{oldBin, "term-old"}, {T("c3"), "term-c3"}, {T("c4"), "term-c4"}} {
		x := x
		wgT.Add(1)
		go func() {
			defer wgT.Done()
			c := exec.Command("sh", "tools/st.sh", "ztermcheck", x[0], T(x[1]))
			c.Stderr = w
			c.Run()
		}()
	}
	wgT.Wait()
	os.WriteFile(T("term-new"), []byte(readFile(filepath.Join(T("rec-new"), "ref-term.txt"))), 0o644)
	rt := &rep{tag: "terminals", w: w}
	rt.say("the nineteen rows, before and after -- ztermcheck, `+set term={name}` on a real pty (zero phase 33):")
	ta := strings.Split(readFile(T("term-old")), "\n")
	tb := strings.Split(readFile(T("term-new")), "\n")
	ta, tb = ta[:len(ta)-1], tb[:len(tb)-1]
	wd := 0
	for _, x := range ta {
		if n := len([]rune(x)); n > wd {
			wd = n
		}
	}
	for k := 0; k < len(ta) && k < len(tb); k++ {
		x, y := ta[k], tb[k]
		op := "->"
		if x == y {
			op = "=="
		}
		pad := wd - len([]rune(x))
		fmt.Fprintf(w, "               %s%s   %s   %s\n", x, strings.Repeat(" ", pad), op, strings.SplitN(y, " -> ", 2)[1])
	}
	ruleErr := func() (string, error) {
		was, now := fileLines(T("term-old")), fileLines(T("term-new"))
		if len(was) != len(now) || len(was) != len(harness.Terms) {
			return "", fmt.Errorf("the two recordings hold %d and %d rows and termcheck names %d",
				len(was), len(now), len(harness.Terms))
		}
		home, _ := os.MkdirTemp("", "ztermcheck-home-")
		defer os.RemoveAll(home)
		d, _ := os.MkdirTemp("", "ztermcheck-")
		defer os.RemoveAll(d)
		out, _, _ := harness.Session(newBin, nil, [][]byte{[]byte(":set term? t_Co?\r"), []byte(":q!\r")},
			"xterm", 20*time.Second, time.Second, d, harness.Env(home), 0, 0)
		def := ""
		for _, line := range strings.Split(harness.DecodeReplace(out), "\n") {
			if k := strings.Index(line, "term="); k >= 0 && !z38VimErr.MatchString(line) {
				def = strings.Fields(line[k:])[0]
				break
			}
		}
		if def == "" {
			return "", fmt.Errorf("the binary answered nothing with no +set term= at all: what a refused " +
				"name leaves the terminal as is unmeasurable, so nothing below is a rule")
		}
		var bad, mvd []string
		for k := range was {
			x, y := was[k], now[k]
			name := x[strings.Index(x, "'")+1 : strings.LastIndex(x, "'")]
			a, b := strings.SplitN(x, " -> ", 2)[1], strings.SplitN(y, " -> ", 2)[1]
			if contains(GONE, name) {
				mvd = append(mvd, name)
				if !contains(strings.Fields(a), "term="+name) {
					bad = append(bad, fmt.Sprintf("%s lost its row but did not resolve BEFORE: %s", pyRepr26(name), a))
				}
				fs := strings.Fields(b)
				hasE, termTok := false, ""
				for _, t := range fs {
					if z38ErrTok.MatchString(t) {
						hasE = true
					}
				}
				for _, t := range fs {
					if strings.HasPrefix(t, "term=") {
						termTok = t
						break
					}
				}
				if !hasE || termTok != def {
					bad = append(bad, fmt.Sprintf("%s lost its row and answered %s, where a refusal and %s "+
						"were due", pyRepr26(name), b, def))
				}
			} else if a != b {
				bad = append(bad, fmt.Sprintf("%s kept its row and moved: %s -> %s", pyRepr26(name), a, b))
			}
		}
		sm, sg := append([]string{}, mvd...), append([]string{}, GONE...)
		sort.Strings(sm)
		sort.Strings(sg)
		if strings.Join(sm, " ") != strings.Join(sg, " ") {
			bad = append(bad, fmt.Sprintf("the rows that moved are %s and the rows removed are %s",
				strings.Join(sm, " "), strings.Join(sg, " ")))
		}
		if len(bad) > 0 {
			return "", fmt.Errorf("the table did not move the way the cut says it must:\n  %s", strings.Join(bad, "\n  "))
		}
		clean := 0
		for _, x := range now {
			if !z38ErrWord.MatchString(x) {
				clean++
			}
		}
		return fmt.Sprintf("exactly %d of the %d rows moved, and they are exactly the names that lost a "+
			"row: each went from term=<itself> to a refusal, leaving the terminal at %s -- "+
			"the same answer the %d names that never had a row already gave.  The other %d "+
			"are byte-identical", len(mvd), len(was), def, len(was)-len(mvd)-clean, len(was)-len(mvd)), nil
	}
	if msg, err := ruleErr(); err != nil {
		for _, l := range strings.Split(err.Error(), "\n") {
			rt.say("%s", l)
		}
		return harness.ErrReported
	} else {
		rt.say("%s", msg)
	}

	// --- 7. THE INSTRUMENT CAN FAIL, in both directions ----------------------------------
	ra := &rep{tag: "ablefail", w: w}
	base := fileLines(T("term-new"))
	one := func(path, name, want string) (string, string, error) {
		rows := fileLines(path)
		if len(rows) != len(base) {
			return "", "", fmt.Errorf("the control recorded %d rows where the output recorded %d", len(rows), len(base))
		}
		var mvd [][2]string
		for k := range base {
			if base[k] != rows[k] {
				mvd = append(mvd, [2]string{base[k], rows[k]})
			}
		}
		if len(mvd) != 1 {
			return "", "", fmt.Errorf("%s the %s row moved %d rows, and exactly 1 was due", want, pyRepr26(name), len(mvd))
		}
		a, b := mvd[0][0], mvd[0][1]
		got := a[strings.Index(a, "'")+1 : strings.LastIndex(a, "'")]
		if got != name {
			return "", "", fmt.Errorf("%s the %s row moved the %s row instead", want, pyRepr26(name), pyRepr26(got))
		}
		return strings.SplitN(a, " -> ", 2)[1], strings.SplitN(b, " -> ", 2)[1], nil
	}
	a3, b3, e3 := one(T("term-c3"), c3Name, "deleting")
	if e3 == nil && (!contains(strings.Fields(a3), "term="+c3Name) || !z38ErrWord.MatchString(b3)) {
		e3 = fmt.Errorf("deleting the %s row went %s -> %s, where resolving -> refused was due", pyRepr26(c3Name), a3, b3)
	}
	var a4, b4 string
	if e3 == nil {
		a4, b4, e3 = one(T("term-c4"), c4Name, "restoring")
		if e3 == nil && (!z38ErrWord.MatchString(a4) || !contains(strings.Fields(b4), "term="+c4Name)) {
			e3 = fmt.Errorf("restoring the %s row went %s -> %s, where refused -> resolving was due", pyRepr26(c4Name), a4, b4)
		}
	}
	if e3 != nil {
		ra.say("%s", e3.Error())
		return harness.ErrReported
	}
	ra.say("deleting the %s row from THIS PHASE'S OWN table moves exactly 1 of %d rows, "+
		"%s -> %s; and putting the %s row back moves exactly 1, %s -> %s.  The "+
		"instrument counts rows in both directions, so a cut of eight that moved seven "+
		"or nine would have been seen", pyRepr26(c3Name), len(base), a3, b3, pyRepr26(c4Name), a4, b4)

	// --- 7b. THE XTERM FAMILY, WHICH NO HARNESS ASKS ABOUT --------------------------------
	rfam := &rep{tag: "family", w: w}
	olo2, ohi2, _ := z38Def(oldT, bOld, "vim_is_xterm")
	tests := z38Prefix.FindAllStringSubmatch(oldT[olo2:ohi2], -1)
	if len(tests) == 0 {
		rfam.say("vim_is_xterm() holds no counted prefix test in the shape this probe " +
			"reads, so the names below cannot be derived")
		return harness.ErrReported
	}
	var fnames, skip []string
	var badT []string
	for _, tt := range tests {
		var n int
		fmt.Sscanf(tt[2], "%d", &n)
		if tt[3] == "==" && len(tt[1]) == n {
			fnames = append(fnames, tt[1])
		}
		if tt[3] == "!=" {
			skip = append(skip, tt[1])
		}
		if tt[3] == "==" && len(tt[1]) != n {
			badT = append(badT, fmt.Sprintf("(%s, %s)", pyRepr26(tt[1]), pyRepr26(tt[2])))
		}
	}
	if len(badT) > 0 {
		rfam.say("vim_is_xterm() compares [%s] against a length that is not the literal's", strings.Join(badT, ", "))
		return harness.ErrReported
	}
	if len(fnames) == 0 {
		rfam.say("vim_is_xterm() accepts no prefix, so this probe would be vacuous")
		return harness.ErrReported
	}
	ask := func(binary, name string) bool {
		home, _ := os.MkdirTemp("", "family-home-")
		defer os.RemoveAll(home)
		d, _ := os.MkdirTemp("", "family-")
		defer os.RemoveAll(d)
		out, _, _ := harness.Session(binary, nil, [][]byte{[]byte(":set term=" + name + "\r"),
			[]byte(":set term? t_Co?\r"), []byte(":q!\r")}, "xterm", 20*time.Second, time.Second, d, harness.Env(home), 0, 0)
		return strings.Contains(harness.DecodeReplace(out), "E522")
	}
	wasR := make([]bool, len(fnames))
	nowR := make([]bool, len(fnames))
	var wgF sync.WaitGroup
	for k, n := range fnames {
		k, n := k, n
		wgF.Add(2)
		go func() { defer wgF.Done(); wasR[k] = ask(oldBin, n) }()
		go func() { defer wgF.Done(); nowR[k] = ask(newBin, n) }()
	}
	wgF.Wait()
	wrongSet := map[string]bool{}
	for k, n := range fnames {
		if wasR[k] {
			wrongSet[n] = true
		}
		if !nowR[k] {
			wrongSet[n] = true
		}
	}
	if len(wrongSet) > 0 {
		rfam.say("the xterm family did not move the way deleting its row says it must: %s", strings.Join(z27Keys(wrongSet), " "))
		return harness.ErrReported
	}
	sk := strings.Join(skip, " ")
	if sk == "" {
		sk = "(none)"
	}
	rfam.say("the `xterm` row was the whole xterm FAMILY, not one name: %d prefixes read "+
		"out of vim_is_xterm() in the source this phase was handed -- %s -- every one "+
		"of them resolved on the binary the phase was handed and every one is E522 "+
		"here.  %s is the one vim_is_xterm() already excluded, and it was E522 either "+
		"way.  None of these names is among the nineteen termcheck asks "+
		"about, which is why the phase owes these probes", len(fnames), strings.Join(fnames, " "), sk)

	// --- 8. SYMBOLS ------------------------------------------------------------------------
	rs := &rep{tag: "symbols", w: w}
	for _, x := range []struct{ src, obj string }{{f, "new.o"}, {oldC, "old.o"}} {
		if out, err := exec.Command("gcc", "-c", "-O0", "-fno-stack-protector", "-o", T(x.obj), x.src).CombinedOutput(); err != nil {
			w.Write(out)
			return harness.ErrReported
		}
	}
	uNew := nmField26(T("new.o"), []string{"-u"}, 1)
	uOld := nmField26(T("old.o"), []string{"-u"}, 1)
	if g, c := minus26(uOld, uNew), minus26(uNew, uOld); len(g)+len(c) > 0 {
		rs.say("the libc surface moved, and this phase frees nothing: gone '%s', new '%s'", z31Words(g), z31Words(c))
		return harness.ErrReported
	}
	extOut, _ := exec.Command("nm", "--extern-only", "--defined-only", T("new.o")).Output()
	var ext []string
	for _, l := range strings.Split(strings.TrimRight(string(extOut), "\n"), "\n") {
		fs := strings.Fields(l)
		if len(fs) > 0 {
			ext = append(ext, fs[len(fs)-1])
		} else {
			ext = append(ext, "")
		}
	}
	sort.Strings(ext)
	if s := z31Words(ext); s != "main " {
		rs.say("the output defines external symbols other than main: %s", s)
		return harness.ErrReported
	}
	rs.say("`nm -u` is THE SAME %d symbols, a comm empty in both directions -- and that is a statement and not a "+
		"disappointment: this phase deletes DATA, three static arrays and %d rows, and data calls nothing.  "+
		"`main` is still the only external symbol", len(uNew), len(GONE))

	// --- 9. THE BOUNDARY ---------------------------------------------------------------------
	rb := &rep{tag: "boundary", w: w}
	type side struct {
		lines, inc int
		iface      []string
	}
	sides := map[string]side{}
	for _, x := range []struct{ side, src string }{{"old", oldC}, {"new", f}} {
		lines := z28Cut(readFile(x.src))
		text := ""
		for _, l := range lines {
			text += l + "\n"
		}
		cp := T("cut-" + x.side + ".c")
		os.WriteFile(cp, []byte(text), 0o644)
		d := 0
		for _, l := range lines {
			if z30Dir.MatchString(l) {
				d++
			}
		}
		inc := 0
		for _, l := range strings.Split(readFile(x.src), "\n") {
			if z38Inc.MatchString(l) {
				inc++
			}
		}
		if d != 0 || len(lines) < 1000 {
			rb.say("the %s cut is %d lines with %d directive(s), and the core has none", x.side, len(lines), d)
			return harness.ErrReported
		}
		c := exec.Command("gcc", "-fsyntax-only", cp)
		var eb strings.Builder
		c.Stderr = &eb
		if err := c.Run(); err != nil {
			rb.say("the %s cut is not a complete translation unit:", x.side)
			for k, l := range strings.Split(strings.TrimRight(eb.String(), "\n"), "\n") {
				if k >= 5 {
					break
				}
				fmt.Fprintf(w, "               %s\n", l)
			}
			return harness.ErrReported
		}
		wo, _ := exec.Command("gcc", "-fsyntax-only", "-Wall", "-Wextra", "-Wno-unused-parameter", cp).CombinedOutput()
		set := map[string]bool{}
		for _, m := range z38IfaceWrn.FindAllStringSubmatch(string(wo), -1) {
			set[m[1]] = true
		}
		sides[x.side] = side{len(lines), inc, z27Keys(set)}
	}
	if sides["old"].inc != sides["new"].inc {
		rb.say("the file had %d #include directives and has %d: this phase removes none and adds none",
			sides["old"].inc, sides["new"].inc)
		return harness.ErrReported
	}
	if strings.Join(sides["old"].iface, "\n") != strings.Join(sides["new"].iface, "\n") {
		rb.say("the core -> host interface moved, and this phase is above the boundary entirely:")
		os.WriteFile(T("iface-old"), []byte(strings.Join(sides["old"].iface, "\n")+"\n"), 0o644)
		os.WriteFile(T("iface-new"), []byte(strings.Join(sides["new"].iface, "\n")+"\n"), 0o644)
		for _, l := range z30Diff(T("iface-old"), T("iface-new")) {
			fmt.Fprintf(w, "               %s\n", l)
		}
		return harness.ErrReported
	}
	rb.say("the cut at the first `#include` is %d -> %d lines, 0 directives and 0 errors under -fsyntax-only either "+
		"side, with %d directives in the file and none above them; and the interface -- the %d names `used but "+
		"never defined`, computed here from the input and never written down -- is UNCHANGED, because every line "+
		"this phase touches is a terminal description in the core",
		sides["old"].lines, sides["new"].lines, sides["old"].inc, len(sides["new"].iface))

	// --- 10. STRUCTURE --------------------------------------------------------------------
	zh := exec.Command("sh", "tools/st.sh", "zhostonly", f)
	zh.Stdout, zh.Stderr = w, w
	if err := zh.Run(); err != nil {
		return harness.ErrReported
	}
	pc := exec.Command("sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols"))
	pc.Stdout, pc.Stderr = w, w
	if err := pc.Run(); err != nil {
		return harness.ErrReported
	}
	return nil
}
