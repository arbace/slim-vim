package check

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
	"sync"
	"time"

	"slimvim.local/tools/internal/cutil"
	"slimvim.local/tools/internal/harness"
)

func init() { register("zero39", Zero39) }

var (
	z39TermpArm  = regexp.MustCompile(`(?m)^[ \t]*if \(termp == nullptr\)$`)
	z39Starting  = regexp.MustCompile(`(?m)^[ \t]*if \(starting != NO_SCREEN\)$`)
	z39Strstr    = regexp.MustCompile(`musl_strstr\(\(char \*\)term, "([^"]*)"\) != nullptr`)
	z39Case      = regexp.MustCompile(`(?m)^[ \t]*case '(.)':$`)
	z39PlusTest  = regexp.MustCompile(`(?m)^[ \t]*if \(argv\[0\]\[0\] == '\+'\)$`)
	z39Else      = regexp.MustCompile(`(?m)^[ \t]*else$`)
	z39TermField = regexp.MustCompile(`(?m)^[ \t]*char_u +\*term;\n`)
	z39Owner     = regexp.MustCompile(`(\w+)\s*(?:\.|->)\s*term\b`)
	z39DotTerm   = regexp.MustCompile(`(?:\.|->)\s*term\b`)
	z39MEPair    = regexp.MustCompile(`(?m)^enum \{ (ME_\w+) = (\d+) \};$`)
	z39MainErr   = regexp.MustCompile(`(?ms)^static char \*\(main_errors\[\]\) =\n\{\n(.*?)^\};\n`)
	z39Exit      = regexp.MustCompile(`--- exit (\S+)`)
	z39StreamN   = regexp.MustCompile(`--- stream (\d+)`)
	z39Promise   = regexp.MustCompile(`not known, defaulting to '([^']*)'`)
	z39TermSp    = regexp.MustCompile(`term=\S+ `)
)

// z39Arm is the heredoc's arm(): set_termname()'s `termp == nullptr` arm,
// its extent in t and its text.
func z39Arm(t string) (int, int, string, bool) {
	lo, hi, ok := cutil.FindDefinition([]byte(t), cutil.Blank([]byte(t)), "set_termname")
	if !ok {
		return 0, 0, "", false
	}
	seg := t[lo:hi]
	b := string(cutil.Blank([]byte(seg)))
	m := z39TermpArm.FindStringIndex(seg)
	if m == nil {
		return 0, 0, "", false
	}
	k := strings.LastIndex(seg[:m[0]], "\n") + 1
	o := strings.Index(b[m[1]:], "{") + m[1]
	c := cutil.Match([]byte(b), o)
	end := c + 1
	if end < len(seg) && seg[end] == '\n' {
		end++
	}
	return lo + k, lo + end, seg[k:end], true
}

func z39Def(t, name string) (int, int) {
	lo, hi, _ := cutil.FindDefinition([]byte(t), cutil.Blank([]byte(t)), name)
	return lo, hi
}

func z39Letters(t string) []string {
	lo, hi := z39Def(t, "command_line_scan")
	seg := t[lo:hi]
	b := string(cutil.Blank([]byte(seg)))
	i := strings.Index(b, "switch (c)")
	if i < 0 {
		return nil
	}
	o := strings.Index(b[i:], "{") + i
	c := cutil.Match([]byte(b), o)
	var out []string
	for _, m := range z39Case.FindAllStringSubmatch(seg[o+1:c], -1) {
		out = append(out, m[1])
	}
	return out
}

// z39Gist is the heredoc's gist(): one record block said in a line.
func z39Gist(block string) string {
	ex, st := "?", "?"
	if m := z39Exit.FindStringSubmatch(block); m != nil {
		ex = m[1]
	}
	if m := z39StreamN.FindStringSubmatch(block); m != nil {
		st = m[1]
	}
	var errl []string
	for _, l := range strings.Split(block, "\n") {
		if l != "" && !strings.HasPrefix(l, "---") && !strings.HasPrefix(l, "VIM - Vi") {
			errl = append(errl, l)
		}
	}
	bl := ""
	if strings.Contains(block, "blocked") {
		bl = "blocked"
	}
	tail := ""
	if len(errl) > 0 {
		tail = ", " + strings.TrimSpace(errl[len(errl)-1])
	}
	return fmt.Sprintf("%s exit %s, %s bytes drawn%s", bl, ex, st, tail)
}

func z39Pad(s string, n int) string {
	if k := len([]rune(s)); k < n {
		return s + strings.Repeat(" ", n-k)
	}
	return s
}

// Zero39 is phase 39's check: -T {term} goes.
func Zero39(w io.Writer, args []string) error {
	if len(args) != 2 {
		return fmt.Errorf("usage: check zero39 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	f := filepath.Join(work, "zero-vim.c")
	oldC := filepath.Join(state, "old.c")
	say := func(tag, format string, a ...any) { (&rep{tag: tag, w: w}).say(format, a...) }
	die := func(tag, format string, a ...any) error {
		say(tag, format, a...)
		return harness.ErrReported
	}
	beforeRaw := strings.TrimRight(readFile(filepath.Join(state, "input-lines")), "\n")
	tmp, err := os.MkdirTemp("", "zero39-")
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

	_ = exec.Command("make", "-C", work, "clean").Run()
	newBin := filepath.Join(work, "zero-vim")
	if _, e := os.Stat(newBin); e == nil {
		return die("build", "the clean did not remove zero-vim, so nothing below would be a recording of this phase")
	}
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		return die("build", "FAILED -- rerun by hand: make -C %s", work)
	}

	// --- the controls -----------------------------------------------------------------
	// tools/cutil.py -- named as a PATH so tools/implhash.sh hashes it into
	// this phase's key.  Do not delete it.
	const CT = "controls"
	newT, oldT := readFile(f), readFile(oldC)
	_, _, blkOld, ok1 := z39Arm(oldT)
	an, zn, blkNew, ok2 := z39Arm(newT)
	if !ok1 || !ok2 {
		return die(CT, "set_termname() has no `termp == nullptr` arm in one of the two texts")
	}
	if blkOld == blkNew {
		return die(CT, "the output keeps the input's refusal arm, so there is nothing to check")
	}
	if strings.Contains(blkNew, "report_default_term") || strings.Contains(blkNew, "NO_SCREEN") {
		return die(CT, "the output's refusal arm still tests `starting` or calls "+
			"report_default_term(), so this phase did not do what it says")
	}
	lo, hi := z39Def(oldT, "report_default_term")
	rdt := oldT[lo:hi]
	if strings.Contains(newT, rdt) {
		return die(CT, "report_default_term() is still in the output, so the sweep did not take it")
	}
	c1 := newT[:an] + blkOld + newT[zn:]
	slo, _ := z39Def(c1, "set_termname")
	c1 = c1[:slo] + rdt + "\n" + c1[slo:]
	if c1 == newT {
		return die(CT, "the arm-restored control changed nothing, so it is not a control")
	}
	os.WriteFile(T("c1.c"), []byte(c1), 0o644)
	mark := func(text, label string) (string, error) {
		a, z, blk, ok := z39Arm(text)
		if !ok {
			return "", die(CT, "set_termname() has no `termp == nullptr` arm in one of the two texts")
		}
		b := string(cutil.Blank([]byte(blk)))
		g := z39Starting.FindStringIndex(blk)
		if g == nil {
			return "", die(CT, "%s: the restored arm does not test `starting`", label)
		}
		o := strings.Index(b[g[1]:], "{") + g[1]
		c := cutil.Match([]byte(b), o)
		nl := strings.Index(blk[o:], "\n") + o + 1
		tail := strings.Index(blk[c:], "\n") + c + 1
		if strings.TrimSpace(blk[tail:]) == "" {
			return "", die(CT, "%s: nothing follows the refusal, so the fallback marker has nowhere to go", label)
		}
		ins := blk[:nl] + "                    host_message(\"NOSCREENARM\\n\", -1, TRUE);\n" +
			blk[nl:tail] + "                host_message(\"FALLBACK\\n\", -1, TRUE);\n" + blk[tail:]
		return text[:a] + ins + text[z:], nil
	}
	iOld, e := mark(oldT, "i-old")
	if e != nil {
		return e
	}
	iNew, e := mark(c1, "i-new")
	if e != nil {
		return e
	}
	os.WriteFile(T("i-old.c"), []byte(iOld), 0o644)
	os.WriteFile(T("i-new.c"), []byte(iNew), 0o644)
	sm := z39Strstr.FindStringSubmatch(newT)
	if sm == nil {
		return die(CT, "the 256-colour name test is not a musl_strstr on `term` in the output")
	}
	if strings.Count(newT, sm[0]) != 1 {
		return die(CT, "the 256-colour name test is not in the output exactly once")
	}
	os.WriteFile(T("cT.c"), []byte(strings.ReplaceAll(newT, sm[0], "(TRUE)")), 0o644)
	os.WriteFile(T("cF.c"), []byte(strings.ReplaceAll(newT, sm[0], "(FALSE)")), 0o644)
	needle := sm[1]
	was, now := z39Letters(oldT), z39Letters(newT)
	if len(was) == 0 {
		return die(CT, "the input's parser accepts no option letter, so this phase removed nothing")
	}
	if len(now) > 0 {
		return die(CT, "the output still accepts the option letter(s) %s", strings.Join(now, " "))
	}
	LETTERS := strings.Join(was, "")
	lo, hi = z39Def(oldT, "command_line_scan")
	seg := oldT[lo:hi]
	b := string(cutil.Blank([]byte(seg)))
	o := strings.Index(b[strings.Index(b, "switch (c)"):], "{") + strings.Index(b, "switch (c)")
	c := cutil.Match([]byte(b), o)
	body := seg[o+1 : c]
	for _, x := range was {
		pat := regexp.MustCompile(`\n[ \t]*case '` + regexp.QuoteMeta(x) + `':\n(?:[^\n]*\n)*?[ \t]*break;\n`)
		if len(pat.FindAllStringIndex(body, -1)) != 1 {
			return die(CT, "the input's switch does not hold one `case %s: ... break;` arm", pyRepr26(x))
		}
		body = pat.ReplaceAllLiteralString(body, "\n")
	}
	c5 := oldT[:lo] + seg[:o+1] + body + seg[c:] + oldT[hi:]
	if c5 == oldT {
		return die(CT, "the letter-only control changed nothing, so it is not a control")
	}
	os.WriteFile(T("c5.c"), []byte(c5), 0o644)
	var dashed []string
	for _, x := range was {
		dashed = append(dashed, "-"+x)
	}
	say(CT, "five controls written from the two texts: the refusal arm restored, "+
		"the instrumented pair, and the 256-colour name test forced each way.  The "+
		"removed option letters are %s, read out of the two parsers", strings.Join(dashed, " "))
	var wgB sync.WaitGroup
	for _, v := range []string{"c1", "c5", "i-old", "i-new", "cT", "cF"} {
		v := v
		wgB.Add(1)
		go func() {
			defer wgB.Done()
			a := append(append(strings.Fields(cflagsS), strings.Fields(ldflagsS)...), "-o", T(v), T(v+".c"))
			cmd := exec.Command("gcc", a...)
			cmd.Env = append(os.Environ(), "SOURCE_DATE_EPOCH=0")
			cmd.Stdout, cmd.Stderr = w, w
			cmd.Run()
		}()
	}
	defer wgB.Wait()

	// --- 1. THE CUT -------------------------------------------------------------------
	const CL = "cmdline"
	var before int
	fmt.Sscanf(strings.TrimSpace(beforeRaw), "%d", &before)
	bnew := string(cutil.Blank([]byte(newT)))
	bold := string(cutil.Blank([]byte(oldT)))
	mentions := func(bt, name string) int {
		return len(regexp.MustCompile(`\b` + name + `\b`).FindAllStringIndex(bt, -1))
	}
	GONE := []string{"want_argument", "mainerr_arg_missing", "ME_GARBAGE", "ME_ARG_MISSING", "requested", "report_default_term"}
	var left []string
	for _, n := range GONE {
		if k := mentions(bnew, n); k > 0 {
			left = append(left, fmt.Sprintf("%s %d", n, k))
		}
	}
	if len(left) > 0 {
		return die(CL, "these were to go and did not: %s", strings.Join(left, ", "))
	}
	for _, n := range GONE {
		if mentions(bold, n) == 0 {
			return die(CL, "%s was not in the input either, so its absence proves nothing", n)
		}
	}
	for _, n := range []string{"ME_UNKNOWN_OPTION", "ME_EXTRA_CMD", "MAX_ARG_CMDS", "exe_commands",
		"p_paste", "did_set_term", "report_term_error", "set_termname"} {
		if mentions(bnew, n) == 0 {
			return die(CL, "%s went, and it is not this phase's", n)
		}
	}
	lo, hi = z39Def(newT, "command_line_scan")
	nseg := newT[lo:hi]
	bseg := string(cutil.Blank([]byte(nseg)))
	if strings.Contains(bseg, "switch") {
		return die(CL, "command_line_scan() still holds a switch")
	}
	for _, name := range []string{"c", "want_argument"} {
		if mentions(bseg, name) > 0 {
			return die(CL, "command_line_scan() still declares `%s`", name)
		}
	}
	if len(z39PlusTest.FindAllStringIndex(nseg, -1)) != 1 {
		return die(CL, "command_line_scan() does not test for exactly one `+`")
	}
	if len(z39Else.FindAllStringIndex(nseg, -1)) != 2 {
		return die(CL, "command_line_scan() does not have the two elses this phase leaves -- the "+
			"`+cmd` arm's inner one and the unknown-option arm")
	}
	if k := mentions(bseg, "ME_UNKNOWN_OPTION"); k != 1 {
		return die(CL, "command_line_scan() answers ME_UNKNOWN_OPTION %d times, and after this "+
			"phase there is ONE arm that answers anything", k)
	}
	say(CL, "the command line is `+{command}` and nothing else: one `+` test, one arm that "+
		"answers ME_UNKNOWN_OPTION, no switch and no option letter -- %s went, and with "+
		"them want_argument, mainerr_arg_missing, ME_GARBAGE, ME_ARG_MISSING and the "+
		"`requested` the fallback needed", strings.Join(dashed, " "))
	mEnd := strings.Index(newT, "} mparm_T;")
	mStart := strings.LastIndex(newT[:mEnd], "{")
	if z39TermField.MatchString(newT[mStart:mEnd]) {
		return die(CL, "mparm_T still has its `term` member")
	}
	ownSet := map[string]bool{}
	for _, m := range z39Owner.FindAllStringSubmatch(bnew, -1) {
		ownSet[m[1]] = true
	}
	owners := z27Keys(ownSet)
	var bad []string
	for _, x := range owners {
		if x == "params" || x == "parmp" {
			bad = append(bad, x)
		}
	}
	if len(bad) > 0 {
		return die(CL, "something still names mparm_T's `term` field: %s", strings.Join(owners, " "))
	}
	if len(owners) == 0 {
		return die(CL, "nothing names a `.term` member at all, so deadfields.py could have taken "+
			"the field and this phase need not have -- read the file")
	}
	say(CL, "mparm_T has no `term` member, and the %d `.term` mentions left all belong to "+
		"another struct (%s): deadfields.py matches by NAME, which is why the member was "+
		"the edit's and not the sweep's", len(z39DotTerm.FindAllStringIndex(bnew, -1)), strings.Join(owners, " "))
	after := strings.Count(newT, "\n")
	if !strings.HasSuffix(newT, "\n") {
		after++
	}
	if after >= before {
		return die(CL, "the file did not shrink: %d -> %d", before, after)
	}
	say(CL, "the file lost %d lines, %d -> %d: the parser arm, the two rows, the field, the "+
		"unreachable fallback and the one function the sweep found under it", before-after, before, after)

	// --- 2. THE ROWS -------------------------------------------------------------------
	const EN = "enums"
	ev := exec.Command("sh", "tools/enumvals.sh", f, T("enums-after"))
	ev.Stdout, ev.Stderr = w, w
	if err := ev.Run(); err != nil {
		return harness.ErrReported
	}
	load := func(p string) ([]string, map[string]string) {
		var order []string
		m := map[string]string{}
		for _, l := range strings.SplitAfter(readFile(p), "\n") {
			if !strings.Contains(l, "=") {
				continue
			}
			l = strings.TrimRight(l, "\n")
			i := strings.Index(l, "=")
			if _, ok := m[l[:i]]; !ok {
				order = append(order, l[:i])
			}
			m[l[:i]] = l[i+1:]
		}
		return order, m
	}
	bOrder, bef := load(filepath.Join(state, "enums-before"))
	_, aft := load(T("enums-after"))
	pairs := func(t string) ([]string, map[string]string) {
		var order []string
		m := map[string]string{}
		for _, p := range z39MEPair.FindAllStringSubmatch(t, -1) {
			if _, ok := m[p[1]]; !ok {
				order = append(order, p[1])
			}
			m[p[1]] = p[2]
		}
		return order, m
	}
	_, wasE := pairs(oldT)
	nowOrder, nowE := pairs(newT)
	var gone []string
	for k := range wasE {
		if _, ok := nowE[k]; !ok {
			gone = append(gone, k)
		}
	}
	sort.Strings(gone)
	if len(gone) == 0 {
		return die(EN, "the output keeps every ME_* enumerator, so nothing here is checked")
	}
	type mvE struct{ a, b string }
	MOVED := map[string]mvE{}
	for _, n := range nowOrder {
		if wv, ok := wasE[n]; !ok || wv != nowE[n] {
			MOVED[n] = mvE{wasE[n], nowE[n]}
		}
	}
	var mk2 []string
	for k := range MOVED {
		mk2 = append(mk2, k)
	}
	sort.Strings(mk2)
	var fail []string
	for _, n := range gone {
		if _, ok := bef[n]; !ok {
			fail = append(fail, fmt.Sprintf("%s was not in the input binary at all, so its removal proves nothing", n))
		}
		if v, ok := aft[n]; ok {
			fail = append(fail, fmt.Sprintf("%s survives in the binary with value %s", n, v))
		}
	}
	pyNone := func(m map[string]string, k string) string {
		if v, ok := m[k]; ok {
			return v
		}
		return "None"
	}
	for _, n := range mk2 {
		x := MOVED[n]
		if bef[n] != x.a || aft[n] != x.b {
			fail = append(fail, fmt.Sprintf("%s is %s -> %s in DWARF and %s -> %s in the source",
				n, pyNone(bef, n), pyNone(aft, n), x.a, x.b))
		}
		ai, _ := strconv.Atoi(x.a)
		bi, _ := strconv.Atoi(x.b)
		if bi != ai-len(gone) {
			fail = append(fail, fmt.Sprintf("%s moved by %d and %d rows went", n, ai-bi, len(gone)))
		}
	}
	var still []string
	for _, n := range bOrder {
		if !contains(gone, n) {
			if _, ok := MOVED[n]; !ok {
				still = append(still, n)
			}
		}
	}
	var movedE, lost []string
	for _, n := range still {
		if v, ok := aft[n]; ok && v != bef[n] {
			movedE = append(movedE, n)
		}
		if _, ok := aft[n]; !ok {
			lost = append(lost, n)
		}
	}
	first8 := func(xs []string) string {
		ys := append([]string{}, xs...)
		sort.Strings(ys)
		if len(ys) > 8 {
			ys = ys[:8]
		}
		return strings.Join(ys, " ")
	}
	if len(movedE) > 0 {
		fail = append(fail, fmt.Sprintf("%d enumerators renumbered and were not to: %s", len(movedE), first8(movedE)))
	}
	if len(lost) > 0 {
		fail = append(fail, fmt.Sprintf("%d enumerators left the binary and were not to: %s", len(lost), first8(lost)))
	}
	rowsM := z39MainErr.FindStringSubmatch(newT)
	nRows := -1
	if rowsM != nil {
		nRows = len(strings.Split(strings.TrimRight(rowsM[1], "\n"), "\n"))
		if rowsM[1] == "" {
			nRows = 0
		}
	}
	if rowsM == nil || nRows != len(nowE)+1 {
		rs := "no"
		if rowsM != nil {
			rs = strconv.Itoa(nRows)
		}
		fail = append(fail, fmt.Sprintf("main_errors[] has %s rows for %d enumerators", rs, len(nowE)))
	}
	if len(fail) > 0 {
		for _, l := range fail {
			say(EN, "%s", l)
		}
		say("", "main_errors[] is indexed by these, and the build cannot see a")
		say("", "wrong index.  DWARF can.")
		return harness.ErrReported
	}
	var mvs []string
	for _, n := range mk2 {
		mvs = append(mvs, fmt.Sprintf("%s %s->%s", n, MOVED[n].a, MOVED[n].b))
	}
	say(EN, "%d in, %d out; %s gone with their rows and %s by exactly %d, the "+
		"number of rows that went; %d unmoved.  main_errors[] is %d rows for %d "+
		"enumerators, the extra one being whim's unreachable leftover",
		len(bef), len(aft), strings.Join(gone, " and "), strings.Join(mvs, " and "),
		len(gone), len(still)-len(movedE), nRows, len(nowE))

	// --- 3. THE RECORDINGS ---------------------------------------------------------------
	wgB.Wait()
	oldBin, _ := filepath.Abs(filepath.Join(state, "old"))
	var wgR sync.WaitGroup
	for _, x := range [][3]string{
		{newBin, f, "rec-new"}, {oldBin, oldC, "rec-old"}, {T("c1"), T("c1.c"), "rec-c1"},
		{T("c5"), T("c5.c"), "rec-c5"}, {T("i-old"), T("i-old.c"), "rec-i-old"}, {T("i-new"), T("i-new.c"), "rec-i-new"},
	} {
		x := x
		wgR.Add(1)
		go func() {
			defer wgR.Done()
			cmd := exec.Command("sh", "tools/zrecord.sh", x[0], x[1], T(x[2]))
			cmd.Stderr = w
			cmd.Run()
		}()
	}
	wgR.Wait()

	// --- 4. THE COMMAND LINE, before and after ----------------------------------------------
	say("argv", "zargv's thirty invocations, before and after -- a row moves if and only if one of its words spells a removed option letter:")
	// tools/zrec.py -- named as a PATH so tools/implhash.sh hashes it into
	// this phase's key.  Do not delete it.
	rdec := func(p string) string { return harness.DecodeReplace([]byte(readFile(p))) }
	nameLetter := func(name string) bool {
		for _, wd := range strings.Fields(name) {
			if strings.HasPrefix(wd, "-") && len(wd) > 1 && strings.ContainsRune(LETTERS, rune(wd[1])) {
				return true
			}
		}
		return false
	}
	var printed []string
	argvErr := func() string {
		wasB := harness.Blocks(rdec(filepath.Join(T("rec-old"), "ref-argv.txt")), "")
		nowB := harness.Blocks(rdec(filepath.Join(T("rec-new"), "ref-argv.txt")), "")
		wk := make([]string, 0, len(wasB))
		for k := range wasB {
			wk = append(wk, k)
		}
		nk := make([]string, 0, len(nowB))
		for k := range nowB {
			nk = append(nk, k)
		}
		sort.Strings(wk)
		sort.Strings(nk)
		if strings.Join(wk, "\x00") != strings.Join(nk, "\x00") {
			return "the two recordings hold different invocations"
		}
		if len(wasB) == 0 {
			return "the recording holds no invocation at all"
		}
		var badA, moved []string
		const UNKNOWN = "Unknown option argument"
		for _, name := range wk {
			a, b := wasB[name], nowB[name]
			want := nameLetter(name)
			if want && a == b {
				badA = append(badA, fmt.Sprintf("%s spells a removed option and did not move", pyRepr26(name)))
			}
			if !want && a != b {
				badA = append(badA, fmt.Sprintf("%s moved and spells no removed option", pyRepr26(name)))
			}
			if want {
				moved = append(moved, name)
				if strings.Contains(a, UNKNOWN) {
					badA = append(badA, fmt.Sprintf("%s was already an unknown option, so moving it proves nothing", pyRepr26(name)))
				}
				if !strings.Contains(b, UNKNOWN) {
					badA = append(badA, fmt.Sprintf("%s is not an unknown option now: %s", pyRepr26(name), z39Gist(b)))
				}
			}
			rhs := "(identical)"
			if a != b {
				rhs = z39Gist(b)
			}
			printed = append(printed, "               "+z39Pad(pyRepr26(name), 22)+" "+z39Pad(z39Gist(a), 46)+" -> "+rhs)
		}
		if len(moved) == 0 {
			return "no invocation spells a removed option letter, so this check is vacuous"
		}
		if len(badA) > 0 {
			return strings.Join(badA, "\n")
		}
		printed = append(printed, fmt.Sprintf("               %d of %d invocations moved, and they are exactly the %d that "+
			"spell %s: each did something else on the binary this phase was handed -- "+
			"started and drew, or answered a DIFFERENT error -- and each is `%s` now",
			len(moved), len(wasB), len(moved), strings.Join(dashed, " or "), UNKNOWN))
		return ""
	}()
	if argvErr != "" {
		// The heredoc's exit message reached the file first: its stdout was
		// block-buffered and flushed only at exit, after stderr.
		for _, l := range append(strings.Split(argvErr, "\n"), printed...) {
			fmt.Fprintf(w, "  argv         %s\n", l)
		}
		return harness.ErrReported
	}
	for _, l := range printed {
		fmt.Fprintln(w, l)
	}
	for _, what := range []string{"screen", "ref-excmds.txt", "ref-pty.txt", "ref-term.txt"} {
		a, bb := filepath.Join(T("rec-old"), what), filepath.Join(T("rec-new"), what)
		var dl []string
		if what == "screen" {
			dl = diffRQ(a, bb)
		} else if !z30Same(a, bb) {
			dl = []string{fmt.Sprintf("Files %s and %s differ", a, bb)}
		}
		if len(dl) > 0 {
			say("argv", "%s moved, and this phase touches only the command line:", what)
			for k, l := range dl {
				if k >= 5 {
					break
				}
				fmt.Fprintf(w, "               %s\n", l)
			}
			return harness.ErrReported
		}
	}
	say("argv", "the 102 screen cases, the Ex-command rows, the pty scenarios and the nineteen terminal rows are the input's byte for byte: this phase moves command lines and nothing else")
	if dl := diffRQ(T("rec-c5"), T("rec-new")); len(dl) > 0 {
		say("letter", "the INPUT with only the option letter removed records something different from this phase's output, so the phase changes behaviour by more than the letter:")
		for k, l := range dl {
			if k >= 10 {
				break
			}
			fmt.Fprintf(w, "               %s\n", l)
		}
		return harness.ErrReported
	}
	if len(diffRQ(T("rec-c5"), T("rec-old"))) == 0 {
		return die("letter", "removing the option letter from the input changed NOTHING, so the instrument cannot see this phase at all")
	}
	say("letter", "the phase decomposed: the INPUT with ONLY the `case` arm deleted -- want_argument, the argument switch, both ME_* rows, the field, the unreachable fallback and `requested` all left in place -- records byte for byte what this phase's output records, and differs from the input.  So the option letter is the whole of what moves behaviour here, and the other five cuts are invisible to every part of a recording")

	// --- 5. THE FALLBACK IS UNREACHABLE, twice ------------------------------------------
	if dl := diffRQ(T("rec-c1"), T("rec-new")); len(dl) > 0 {
		say("fallback", "the output with the refusal arm RESTORED records something different, so removing it was not neutral:")
		for k, l := range dl {
			if k >= 10 {
				break
			}
			fmt.Fprintf(w, "               %s\n", l)
		}
		return harness.ErrReported
	}
	filesWith := func(dir, tok string) int {
		n := 0
		for _, rel := range walkFiles(dir) {
			if strings.Contains(readFile(filepath.Join(dir, rel)), tok) {
				n++
			}
		}
		return n
	}
	hitOld := filesWith(T("rec-i-old"), "FALLBACK")
	hitNew := filesWith(T("rec-i-new"), "FALLBACK")
	rowsOld := 0
	for _, l := range strings.Split(readFile(filepath.Join(T("rec-i-old"), "ref-argv.txt")), "\n") {
		if strings.Contains(l, "FALLBACK") {
			rowsOld++
		}
	}
	blocks := harness.Blocks(rdec(filepath.Join(T("rec-old"), "ref-argv.txt")), "")
	want := 0
	for n, bl := range blocks {
		if strings.Contains(bl, "not known") {
			if !nameLetter(n) {
				fmt.Fprintf(w, "%s fell back and spells no removed option letter\n", pyRepr26(n))
				return die("fallback", "the input's own recording does not say which rows fell back")
			}
			want++
		}
	}
	if hitNew != 0 {
		return die("fallback", "the marker fires in %d file(s) of the control built from THIS PHASE'S output, where 0 was due -- the fallback is reachable", hitNew)
	}
	if hitOld == 0 || rowsOld != want {
		return die("fallback", "the identical marker fires in %d file(s) and %d command row(s) of the INPUT, where %d command rows were due: the instrument cannot fail, so it is not evidence", hitOld, rowsOld, want)
	}
	say("fallback", "the three statements after the refusal cannot run, TWICE OVER: the output with the whole arm RESTORED -- report_default_term() and all -- records byte for byte what the output records, over every screen case, command row, pty scenario and terminal row; and the identical marker inside the fallback, reached through host_message(), fires in %d command row(s) of the INPUT -- the ones that name a terminal on the command line, which is the ONLY way in -- and in %d records of the control", rowsOld, hitNew)

	// --- 6. THE ARM THAT STAYS IS ENTERED ---------------------------------------------------
	ask := func(binary, name string) string {
		home, _ := os.MkdirTemp("", "zero39-home-")
		defer os.RemoveAll(home)
		d, _ := os.MkdirTemp("", "zero39-")
		defer os.RemoveAll(d)
		out, _, _ := harness.Session(binary, []string{"+set term=" + name},
			[][]byte{[]byte(":set term? t_Co?\r"), []byte(":q!\r")}, "xterm", 20*time.Second, time.Second, d, harness.Env(home), 0, 0)
		return harness.DecodeReplace(out)
	}
	pool := func(n int, jobs []func()) {
		sem := make(chan struct{}, n)
		var wg sync.WaitGroup
		for _, j := range jobs {
			j := j
			wg.Add(1)
			sem <- struct{}{}
			go func() { defer wg.Done(); defer func() { <-sem }(); j() }()
		}
		wg.Wait()
	}
	armErr := func() string {
		answers := make([]string, len(harness.Terms))
		var jobs []func()
		for k, t := range harness.Terms {
			k, t := k, t
			jobs = append(jobs, func() { answers[k] = ask(newBin, t) })
		}
		pool(8, jobs)
		name := ""
		for k, t := range harness.Terms {
			if t != "" && strings.Contains(answers[k], "E522") {
				name = t
				break
			}
		}
		if name == "" {
			return "the new binary refuses no terminal name at all, so there is no run-time refusal to measure"
		}
		marks := map[string]string{}
		plain := map[string]string{}
		var mu sync.Mutex
		var jobs2 []func()
		for _, x := range [][2]string{{"i-old", T("i-old")}, {"i-new", T("i-new")}} {
			x := x
			jobs2 = append(jobs2, func() { s := ask(x[1], name); mu.Lock(); marks[x[0]] = s; mu.Unlock() })
		}
		for _, x := range [][2]string{{"old", oldBin}, {"new", newBin}} {
			x := x
			jobs2 = append(jobs2, func() { s := ask(x[1], name); mu.Lock(); plain[x[0]] = s; mu.Unlock() })
		}
		pool(4, jobs2)
		for _, k := range []string{"i-old", "i-new"} {
			if !strings.Contains(marks[k], "NOSCREENARM") {
				return fmt.Sprintf("%s does not take the no-screen test's arm on `:set term=%s`, so "+
					"the fold this phase made is not ALWAYS", k, name)
			}
			if strings.Contains(marks[k], "FALLBACK") {
				return fmt.Sprintf("%s reaches the fallback at run time", k)
			}
		}
		for _, k := range []string{"old", "new"} {
			if !strings.Contains(plain[k], "E522") {
				return fmt.Sprintf("%s does not refuse `:set term=%s`", k, name)
			}
			if !strings.Contains(plain[k], "'"+name+"' not known") {
				return fmt.Sprintf("%s does not report the name at all", k)
			}
		}
		wm := z39Promise.FindStringSubmatch(plain["old"])
		nm := z39Promise.FindStringSubmatch(plain["new"])
		if wm == nil {
			return "the binary this phase was handed did not promise a default, so there was nothing here to take away"
		}
		if nm != nil {
			return fmt.Sprintf("the new binary still promises %s, and there is no fallback to make that true", pyRepr26(nm[1]))
		}
		to, tn := z39TermSp.FindAllString(plain["old"], -1), z39TermSp.FindAllString(plain["new"], -1)
		if strings.Join(to, "\x00") != strings.Join(tn, "\x00") {
			return fmt.Sprintf("the terminal the editor is left at moved: %s -> %s", z27ReprList(to), z27ReprList(tn))
		}
		return fmt.Sprintf("OK`:set term=%s` on a real pty takes the no-screen arm on BOTH instrumented "+
			"builds and reaches the fallback on neither: the test this phase folded is "+
			"true wherever the arm is reached.  report_term_error() still runs -- it is "+
			"the run-time refusal's and not the fallback's -- and says `'%s' not known` "+
			"where it said `defaulting to '%s'`, with E522 and the terminal it is left at "+
			"unchanged", name, name, wm[1])
	}()
	if strings.HasPrefix(armErr, "OK") {
		say("arm", "%s", armErr[2:])
	} else {
		return die("arm", "%s", armErr)
	}

	// --- 7. THE 256-COLOUR TEST DOES NOT FOLD -----------------------------------------------
	var wgT sync.WaitGroup
	for _, x := range [][2]string{{T("cT"), "term-cT"}, {T("cF"), "term-cF"}} {
		x := x
		wgT.Add(1)
		go func() {
			defer wgT.Done()
			cmd := exec.Command("sh", "tools/st.sh", "ztermcheck", x[0], T(x[1]))
			cmd.Stderr = w
			cmd.Run()
		}()
	}
	wgT.Wait()
	colErr := func() string {
		lines := func(p string) []string {
			s := strings.TrimRight(readFile(p), "\n")
			if s == "" {
				return nil
			}
			return strings.Split(s, "\n")
		}
		rows := lines(filepath.Join(T("rec-new"), "ref-term.txt"))
		movedR := func(p string) ([]string, string) {
			other := lines(p)
			if len(other) != len(rows) {
				return nil, fmt.Sprintf("a control recorded %d rows where the output recorded %d", len(other), len(rows))
			}
			var out []string
			for k := range rows {
				if rows[k] != other[k] {
					a := rows[k]
					out = append(out, a[strings.Index(a, "'")+1:strings.LastIndex(a, "'")])
				}
			}
			return out, ""
		}
		up, e1 := movedR(T("term-cT"))
		if e1 != "" {
			return e1
		}
		down, e2 := movedR(T("term-cF"))
		if e2 != "" {
			return e2
		}
		if len(up) == 0 || len(down) == 0 {
			return fmt.Sprintf("forcing the name test TRUE moved %d rows and FALSE moved %d: a test "+
				"that cannot be seen either way is one this phase could have folded", len(up), len(down))
		}
		both := map[string]bool{}
		for _, x := range up {
			if contains(down, x) {
				both[x] = true
			}
		}
		if len(both) > 0 {
			return fmt.Sprintf("%s moves whichever way the test is forced, so neither control says "+
				"what the test decides", strings.Join(z27Keys(both), " "))
		}
		var resolving []string
		for _, r := range rows {
			if !strings.Contains(r, "E5") {
				resolving = append(resolving, r[strings.Index(r, "'")+1:strings.LastIndex(r, "'")])
			}
		}
		extraU := map[string]bool{}
		for _, x := range up {
			if !contains(resolving, x) {
				extraU[x] = true
			}
		}
		if len(extraU) > 0 {
			return fmt.Sprintf("forcing the test TRUE moved a row that does not resolve at all: %s", strings.Join(z27Keys(extraU), " "))
		}
		askTC := func(binary, name string) string {
			s := ask(binary, name)
			var got []string
			for _, line := range strings.Split(s, "\n") {
				for _, kw := range []string{"term=", "t_Co="} {
					if i := strings.Index(line, kw); i >= 0 {
						got = append(got, strings.Fields(line[i:])[0])
					}
				}
			}
			return strings.Join(got, " ")
		}
		var names []string
		for _, n := range resolving {
			names = append(names, "builtin_"+n)
		}
		wasA := make([]string, len(names))
		nowA := make([]string, len(names))
		var jobs []func()
		for k, n := range names {
			k, n := k, n
			jobs = append(jobs, func() { wasA[k] = askTC(oldBin, n) })
		}
		pool(2*len(names), jobs)
		jobs = nil
		for k, n := range names {
			k, n := k, n
			jobs = append(jobs, func() { nowA[k] = askTC(newBin, n) })
		}
		pool(2*len(names), jobs)
		var diff []string
		for k := range names {
			if wasA[k] != nowA[k] {
				diff = append(diff, names[k])
			}
		}
		if len(diff) > 0 {
			return fmt.Sprintf("folding `requested` into `term` moved %s, which is exactly the input "+
				"the stripped prefix makes different", strings.Join(diff, " "))
		}
		anyA := false
		for _, a := range wasA {
			if a != "" {
				anyA = true
			}
		}
		if !anyA {
			return "the `builtin_` spellings answered nothing on either binary, so the neutrality of the fold is untested"
		}
		d3 := down
		if len(d3) > 3 {
			d3 = d3[:3]
		}
		return fmt.Sprintf("OKthe %s test does NOT fold and this phase does not pretend it does: forcing it "+
			"TRUE moves %d of %d terminal rows (%s) and forcing it FALSE moves %d (%s...), "+
			"so both arms are reached at run time and either fold would be a behaviour "+
			"change.  And folding `requested` into `term` is neutral where the two differ: "+
			"%s answer identically on both binaries -- %s", pyRepr26(needle), len(up), len(rows),
			strings.Join(up, " "), len(down), strings.Join(d3, " "), strings.Join(names, " and "),
			strings.Join(nowA, " / "))
	}()
	if strings.HasPrefix(colErr, "OK") {
		say("colours", "%s", colErr[2:])
	} else {
		return die("colours", "%s", colErr)
	}

	// --- 8. SYMBOLS ---------------------------------------------------------------------------
	for _, x := range []struct{ src, obj string }{{f, "new.o"}, {oldC, "old.o"}} {
		if out, err := exec.Command("gcc", "-c", "-O0", "-fno-stack-protector", "-o", T(x.obj), x.src).CombinedOutput(); err != nil {
			w.Write(out)
			return harness.ErrReported
		}
	}
	uNew := nmField26(T("new.o"), []string{"-u"}, 1)
	uOld := nmField26(T("old.o"), []string{"-u"}, 1)
	if g, cm := minus26(uOld, uNew), minus26(uNew, uOld); len(g)+len(cm) > 0 {
		return die("symbols", "the libc surface moved, and this phase frees nothing: gone '%s', new '%s'", z31Words(g), z31Words(cm))
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
		return die("symbols", "the output defines external symbols other than main: %s", s)
	}
	say("symbols", "`nm -u` is THE SAME %d symbols, a comm empty in both directions -- and that is a statement and not a disappointment: what this phase removes is a parser arm and an unreachable fallback, and neither was anything's last caller.  `main` is still the only external symbol", len(uNew))

	// --- 9. THE BOUNDARY ------------------------------------------------------------------------
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
			return die("boundary", "the %s cut is %d lines with %d directive(s), and the core has none", x.side, len(lines), d)
		}
		cmd := exec.Command("gcc", "-fsyntax-only", cp)
		var eb strings.Builder
		cmd.Stderr = &eb
		if err := cmd.Run(); err != nil {
			say("boundary", "the %s cut is not a complete translation unit:", x.side)
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
		return die("boundary", "the file had %d #include directives and has %d: this phase removes none and adds none",
			sides["old"].inc, sides["new"].inc)
	}
	if strings.Join(sides["old"].iface, "\n") != strings.Join(sides["new"].iface, "\n") {
		say("boundary", "the core -> host interface moved, and this phase is above the boundary entirely:")
		os.WriteFile(T("iface-old"), []byte(strings.Join(sides["old"].iface, "\n")+"\n"), 0o644)
		os.WriteFile(T("iface-new"), []byte(strings.Join(sides["new"].iface, "\n")+"\n"), 0o644)
		for _, l := range z30Diff(T("iface-old"), T("iface-new")) {
			fmt.Fprintf(w, "               %s\n", l)
		}
		return harness.ErrReported
	}
	say("boundary", "the cut at the first `#include` is %d -> %d lines, 0 directives and 0 errors under -fsyntax-only either "+
		"side, with %d directives in the file and none above them; and the interface -- the %d names `used but "+
		"never defined`, computed here from the input and never written down -- is UNCHANGED, because every line "+
		"this phase touches is the core talking to itself",
		sides["old"].lines, sides["new"].lines, sides["old"].inc, len(sides["new"].iface))

	// --- 10. STRUCTURE --------------------------------------------------------------------------
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
