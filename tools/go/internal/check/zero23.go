package check

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"slimvim.local/tools/internal/harness"
)

func init() { register("zero23", Zero23) }

// z23Spans is the heredoc's literal_spans(): every string and character
// literal, escapes skipped, refusing one a newline or the end of the text cuts.
func z23Spans(t string) ([][2]int, bool) {
	var out [][2]int
	i, n := 0, len(t)
	for i < n {
		c := t[i]
		if c == '"' || c == '\'' {
			j := i + 1
			for j < n {
				if t[j] == '\\' {
					j += 2
					continue
				}
				if t[j] == c || t[j] == '\n' {
					break
				}
				j++
			}
			if j >= n || t[j] != c {
				return nil, false
			}
			out = append(out, [2]int{i, j + 1})
			i = j + 1
		} else {
			i++
		}
	}
	return out, true
}

func z23Outside(t string, S [][2]int, name string) int {
	starts := make([]int, len(S))
	for i, s := range S {
		starts[i] = s[0]
	}
	k := 0
	for _, m := range regexp.MustCompile(`\b` + name + `\b`).FindAllStringIndex(t, -1) {
		j := sort.SearchInts(starts, m[0]+1) - 1
		if !(j >= 0 && S[j][0] <= m[0] && m[0] < S[j][1]) {
			k++
		}
	}
	return k
}

// z23CmpL is `cmp -l a b | wc -l`: the bytes that differ over the common length.
func z23CmpL(a, b []byte) int {
	n := len(a)
	if len(b) < n {
		n = len(b)
	}
	d := 0
	for i := 0; i < n; i++ {
		if a[i] != b[i] {
			d++
		}
	}
	return d
}

// Zero23 is phase 23's check: `nullptr` and `usize`.
func Zero23(w io.Writer, args []string) error {
	if len(args) < 2 {
		return fmt.Errorf("usage: check zero23 <work-dir> <state-dir>")
	}
	work, state := args[0], args[1]
	r := &rep{tag: "language", w: w}
	f := filepath.Join(work, "zero-vim.c")
	beforeLines := strings.TrimSpace(readFile(filepath.Join(state, "input-lines")))
	tmp, err := os.MkdirTemp("", "zero23")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	mk := readFile(filepath.Join(work, "Makefile"))
	cflags, ldflags := strings.Fields(z9Flag(mk, "CFLAGS")), strings.Fields(z9Flag(mk, "LDFLAGS"))
	newC, oldC := readFile(f), readFile(filepath.Join(state, "old.c"))
	stop := func(format string, a ...any) error { r.say(format, a...); return harness.ErrReported }
	sde := append(os.Environ(), "SOURCE_DATE_EPOCH=0")
	build := func(out, src, log string) chan error {
		ch := make(chan error, 1)
		go func() {
			a := append(append(append([]string{}, cflags...), ldflags...), "-o", out, src)
			c := exec.Command("gcc", a...)
			c.Env = sde
			if log != "" {
				lf, _ := os.Create(log)
				defer lf.Close()
				c.Stderr = lf
			}
			ch <- c.Run()
		}()
		return ch
	}
	newB := build(filepath.Join(tmp, "new"), f, "")

	c1, n1 := newC, 0
	c1 = regexp.MustCompile(`\bNULL\b`).ReplaceAllStringFunc(newC, func(string) string { n1++; return "nullptr" })
	if n1 != 3 {
		return stop("c1 rewrote %d `NULL`, expected the three inside string literals -- there is nothing else left for a literal-unaware sed to find, so this control would not be the control", n1)
	}
	const sig = "musl_memcpy(void *dest, const void *src, usize n)"
	if strings.Count(newC, sig) != 1 {
		return stop("the vendored signature `%s` is not in the output exactly once", sig)
	}
	c2 := strings.Replace(newC, sig, strings.ReplaceAll(sig, "usize", "size_t"), 1)
	for _, p := range [][2]string{{"c1", c1}, {"c2", c2}} {
		if p[1] == newC {
			return stop("%s changed nothing", p[0])
		}
		os.WriteFile(filepath.Join(tmp, p[0]+".c"), []byte(p[1]), 0o644)
	}
	r.say("two controls written: c1 the literal exclusion removed -- the plain sed, which rewrites the three strings -- and c2 one vendored `usize` reverted to `size_t`")
	ctl := map[string]chan error{}
	for _, c := range []string{"c1", "c2"} {
		ctl[c] = build(filepath.Join(tmp, c), filepath.Join(tmp, c+".c"), filepath.Join(tmp, c+".log"))
	}
	defer func() {
		<-newB
		for _, ch := range ctl {
			select {
			case <-ch:
			default:
			}
		}
	}()

	// --- 1. the source, as arithmetic on the input ---------------------------
	var before int
	fmt.Sscan(beforeLines, &before)
	var fail []string
	mentions := func(t, name string) int {
		return len(regexp.MustCompile(`\b` + name + `\b`).FindAllString(t, -1))
	}
	So, ok1 := z23Spans(oldC)
	if !ok1 {
		return stop("an unterminated literal in %s", f)
	}
	Sn, ok2 := z23Spans(newC)
	if !ok2 {
		return stop("an unterminated literal in %s", f)
	}
	inNull, inSize := mentions(oldC, "NULL"), mentions(oldC, "size_t")
	litNull := inNull - z23Outside(oldC, So, "NULL")
	litSize := inSize - z23Outside(oldC, So, "size_t")
	if litNull != 3 || litSize != 0 {
		fail = append(fail, fmt.Sprintf("the input has %d `NULL` and %d `size_t` inside literals, expected 3 and 0 -- the exclusion rule is about a set this phase has looked at", litNull, litSize))
	}
	for _, p := range []struct {
		name string
		want int
		why  string
	}{
		{"NULL", litNull, fmt.Sprintf("exactly the literals: the E1507 message, \"[NULL]\" and \"NULL\", and nothing else in %d", inNull)},
		{"size_t", 0, fmt.Sprintf("every one of the %d, there being no literal to spare", inSize)},
		{"nullptr", inNull - litNull, "one at each `NULL` outside a literal"},
		{"usize", inSize + 1, "one at each `size_t`, plus its own typedef"},
		{"typeof", 1, "the typedef and nowhere else"},
	} {
		if m := mentions(newC, p.name); m != p.want {
			fail = append(fail, fmt.Sprintf("`%s` has %d mentions, expected %d -- %s", p.name, m, p.want, p.why))
		}
	}
	want := []string{`"E1507: Internal error: ap_types or ap_types[idx] is NULL: %d: %s"`, `"[NULL]"`, `"NULL"`}
	for _, lit := range want {
		if strings.Count(oldC, lit) != 1 || strings.Count(newC, lit) != 1 {
			fail = append(fail, fmt.Sprintf("the literal %s occurs %d times in the input and %d in the output, and must occur once in each -- a rename that reached inside a string changes DATA", lit, strings.Count(oldC, lit), strings.Count(newC, lit)))
		}
	}
	litsWith := func(t string, S [][2]int, re *regexp.Regexp) []string {
		var o []string
		for _, s := range S {
			if re.MatchString(t[s[0]:s[1]]) {
				o = append(o, t[s[0]:s[1]])
			}
		}
		return o
	}
	if strings.Join(litsWith(newC, Sn, regexp.MustCompile(`\b(NULL|nullptr)\b`)), "\x00") != strings.Join(litsWith(oldC, So, regexp.MustCompile(`\bNULL\b`)), "\x00") {
		fail = append(fail, "the literals mentioning `NULL` are not the same literals in the same order as in the input")
	}
	const typedef = "typedef typeof(sizeof(0)) usize;"
	L := strings.Split(newC, "\n")
	if strings.Count(newC, typedef+"\n") != 1 || len(L) < 13 || L[12] != typedef {
		fail = append(fail, fmt.Sprintf("`%s` is not on line 13 of the output exactly once -- it belongs directly below the includes, so that when phase 26 moves them to the bottom it is the first line of the core", typedef))
	}
	intro := regexp.MustCompile(`(?m)^[^\n]*\btypedef\b[^\n]*\busize\b[^\n]*$`).FindAllString(newC, -1)
	if len(intro) != 1 || intro[0] != typedef {
		s := strings.Join(intro, " / ")
		if s == "" {
			s = "nothing"
		}
		fail = append(fail, fmt.Sprintf("`usize` is introduced by %s and not by one typedef -- it is a TYPE NAME and not a static object", s))
	}
	if len(L)-1 != before+2 {
		fail = append(fail, fmt.Sprintf("the file is %d lines and the input was %d -- expected exactly two more, the typedef and its blank line", len(L)-1, before))
	}
	if regexp.MustCompile(`\(\s*void\s*\*\s*\)\s*nullptr\b`).MatchString(newC) {
		fail = append(fail, "a `(void *)nullptr` survives: the cast existed for the variadic hazard of an UNTYPED null constant, and `nullptr` is typed")
	}
	nCast := len(regexp.MustCompile(`\(void \*\)NULL\b`).FindAllString(oldC, -1))
	if nCast != 30 {
		fail = append(fail, fmt.Sprintf("the input has %d `(void *)NULL`, and this phase was measured on 30", nCast))
	}
	rows := z6RowRe.FindAllString(newC, -1)
	got, _ := harness.CommandNamesIn([]byte(newC), "zero-vim.c")
	if len(rows) != 98 || len(got) != 98 {
		fail = append(fail, "cmdnames[] is not the 98 rows phase 10 left -- this phase touches no Ex command")
	}
	if i := strings.Index(newC, "static struct vimoption options[]"); i >= 0 {
		j := strings.Index(newC[i:], "\n};")
		if m := len(z12RowRe.FindAllString(newC[i:i+j], -1)); m != 107 {
			fail = append(fail, fmt.Sprintf("options[] has %d rows, expected the 107 phase 20 left -- this phase removes no option", m))
		}
	}
	var d []string
	for _, l := range L {
		if strings.HasPrefix(l, "#") {
			d = append(d, l)
		}
	}
	dirOK := len(d) == 11 && len(L) >= 11 && strings.Join(L[:11], "\n") == strings.Join(d, "\n")
	for _, l := range d {
		if !strings.HasPrefix(l, "#include <") {
			dirOK = false
		}
	}
	if !dirOK {
		fail = append(fail, "the output does not have exactly the eleven `#include` directives phase 21 left, on its first eleven lines.  MOVING THEM IS PHASE 26")
	}
	for k := 1; k < len(L); k++ {
		if L[k] == "" && L[k-1] == "" {
			fail = append(fail, "there is a run of two blank lines, which canon.sh should have taken")
			break
		}
	}
	if len(fail) > 0 {
		for _, l := range fail {
			r.say("%s", l)
		}
		return harness.ErrReported
	}
	r.say("`NULL` %d -> %d and `nullptr` 0 -> %d; `size_t` %d -> 0 and `usize` 0 -> %d, the extra one being its own typedef.  Every count is computed FROM THE INPUT, so this is a check on the phase and not on whatever it was handed", inNull, litNull, inNull-litNull, inSize, inSize+1)
	r.cont("THE THREE LITERALS ARE UNCHANGED, and they are the whole of what a line-wise sed would have got wrong: %s", strings.Join(want, ", "))
	r.cont("%d `(void *)NULL` became plain `nullptr` -- the cast existed for the variadic hazard of an untyped null constant, and there is not one `(void *)nullptr` left; eleven vendored signatures took `usize` with everything else, and they have been the core's own since phases 14 and 15, so no contract with anybody moved", nCast)
	r.cont("eleven #includes still on the first eleven lines -- MOVING THEM IS PHASE 26 -- cmdnames[] 98, options[] 107, %d -> %d lines and no run of two blank lines", before, len(L)-1)

	// --- 2. C23, and that `usize` IS `size_t` --------------------------------
	line13 := ""
	if len(L) >= 13 {
		line13 = L[12]
	}
	if line13 != typedef {
		return stop("line 13 of the output is not the typedef: %s", line13)
	}
	g := filepath.Join(tmp, "g.c")
	os.WriteFile(g, []byte(line13+"\n"+
		"static usize probe(void) { return sizeof(usize); }\n"+
		"#include <stddef.h>\n"+
		"static_assert(_Generic((usize)0, size_t: 1, default: 0), \"usize IS size_t\");\n"+
		"static_assert(sizeof(nullptr) == sizeof(void *), \"nullptr is pointer-sized\");\n"+
		"int main(void) { return (int)probe() - (int)sizeof(size_t); }\n"), 0o644)
	for _, std := range []string{"DEFAULT", "-std=c23"} {
		a := []string{"-Wall", "-Wextra", "-Wpedantic", "-o", filepath.Join(tmp, "g"), g}
		if std != "DEFAULT" {
			a = append([]string{std}, a...)
		}
		c := exec.Command("gcc", a...)
		var eb bytes.Buffer
		c.Stderr = &eb
		if c.Run() != nil {
			r.say("the typedef is REFUSED under %s, and this phase requires it:", std)
			ls := strings.Split(strings.TrimRight(eb.String(), "\n"), "\n")
			for _, l := range head(ls, 4) {
				fmt.Fprintln(w, "               "+l)
			}
			return harness.ErrReported
		}
	}
	if exec.Command(filepath.Join(tmp, "g")).Run() != nil {
		return stop("the probe ran and disagreed: sizeof(usize) is not sizeof(size_t)")
	}
	for _, std := range []string{"-std=c11", "-std=c99"} {
		if exec.Command("gcc", std, "-o", "/dev/null", g).Run() == nil {
			r.say("the typedef is ACCEPTED under %s, and it must not be:", std)
			r.cont("\"typeof\" is C23, and a check that passes under C11 is not")
			r.cont("stating the dependency this file has.")
			return harness.ErrReported
		}
	}
	r.say("C23 IS A REAL DEPENDENCY AND IT IS STATED: the typedef taken out of line 13 of the output compiles under gcc's default and -std=c23 and is REFUSED under -std=c11 and -std=c99.  It is not a NEW dependency -- this file already needs C23 for `enum : long`, `static_assert` and lowercase `bool`/`true`/`false`")
	r.say("AND THE DERIVATION HOLDS: with the real <stddef.h> arriving after it in the same translation unit, _Generic((usize)0, size_t: 1, default: 0) is 1 -- `usize` IS `size_t`, the same TYPE and not merely the same width, on any target rather than on this one -- and sizeof(nullptr) == sizeof(void *), which is why the thirty casts could go")

	// --- 3. the compile, the linkage and the libc surface --------------------
	beforeU := readFile(filepath.Join(state, "symbols", "undefined"))
	if err := run(w, "sh", "tools/phasecheck.sh", work, f, filepath.Join(state, "symbols")); err != nil {
		return harness.ErrReported
	}
	afterU := readFile(".cache/symbols/last/undefined")
	if beforeU != afterU {
		b, a := strings.Fields(beforeU), strings.Fields(afterU)
		r.say("the libc surface moved, and RENAMING A TYPE CANNOT MOVE IT:")
		r.cont("gone: %s", trSpace(comm23(b, a)))
		r.cont("came: %s", trSpace(comm23(a, b)))
		return harness.ErrReported
	}
	r.say("symbols %s -> %s, and the set is IDENTICAL as a cmp -- nothing left and nothing arrived; main is still the only external symbol",
		strings.TrimSpace(readFile(".cache/symbols/last/before")), strings.TrimSpace(readFile(".cache/symbols/last/after")))

	// --- 4. the binary -------------------------------------------------------
	bl := &rep{tag: "build", w: w}
	_ = exec.Command("make", "-C", work, "clean").Run()
	if _, err := os.Stat(filepath.Join(work, "zero-vim")); err == nil {
		bl.say("the clean did not remove zero-vim, so a 'rebuild' below could be no rebuild at all")
		return harness.ErrReported
	}
	if err := exec.Command("make", "-C", work).Run(); err != nil {
		bl.say("FAILED -- rerun by hand: make -C %s", work)
		return harness.ErrReported
	}
	bin := filepath.Join(work, "zero-vim")
	bl.say("ok, %s -> %d lines, %d bytes", beforeLines, countLines([]byte(readFile(f))), sizeOf(bin))
	if err := <-newB; err != nil {
		newB <- err
		return stop("the reproducible build of the output failed")
	}
	newB <- nil
	oldBin, newBin := filepath.Join(state, "old"), filepath.Join(tmp, "new")
	oldSize, newSize := sizeOf(oldBin), sizeOf(newBin)
	if newSize < 500000 || oldSize < 500000 {
		return stop("one of the two binaries is %d / %d bytes, which is not an editor -- a cmp of two files nothing wrote passes", oldSize, newSize)
	}
	if newSize != sizeOf(bin) {
		return stop("the reproducible build is %d bytes and make produced %d: the two differ by more than a timestamp, so the comparison below would not be about this boundary", newSize, sizeOf(bin))
	}
	ob, nb := []byte(readFile(oldBin)), []byte(readFile(newBin))
	if !bytes.Equal(ob, nb) {
		r.say("THE BINARY MOVED.  This phase renames two names and deletes")
		for _, l := range []string{
			"thirty casts whose reason has evaporated, and must change no",
			"code at all, so the two binaries -- the input's and the",
			"output's, both built with SOURCE_DATE_EPOCH=0 and the",
			"boundary's own flags -- must be the same bytes.",
			fmt.Sprintf("%d in, %d out.  The GNU build-id note is a hash of", oldSize, newSize),
			"the whole image and sits near the front, so the first difference",
			"below is always that note and never the change itself:"} {
			r.cont("%s", l)
		}
		o, _ := exec.Command("cmp", oldBin, newBin).CombinedOutput()
		for _, l := range strings.Split(strings.TrimRight(string(o), "\n"), "\n") {
			fmt.Fprintln(w, "               "+l)
		}
		return harness.ErrReported
	}
	r.say("THE BINARY IS BYTE-IDENTICAL, %d bytes either side -- tier 1 of CLAUDE.md's verification table, and the whole of this phase's evidence.  A byte-identical binary subsumes every screen case, every Ex-command row, every command line and every pty scenario at once, because the program that would be run is the same program; tools/zerodelta.sh --phase 23 runs next and corroborates rather than proves", newSize)

	// --- 5. the controls -----------------------------------------------------
	for _, c := range []string{"c1", "c2"} {
		<-ctl[c]
		ctl[c] <- nil
	}
	for _, c := range []string{"c1", "c2"} {
		if fi, e := os.Stat(filepath.Join(tmp, c)); e != nil || fi.Mode()&0o111 == 0 {
			r.say("the control %s did not build:", c)
			for _, l := range head(strings.Split(strings.TrimRight(readFile(filepath.Join(tmp, c+".log")), "\n"), "\n"), 5) {
				fmt.Fprintln(w, "               "+l)
			}
			return harness.ErrReported
		}
	}
	c1b := []byte(readFile(filepath.Join(tmp, "c1")))
	if bytes.Equal(ob, c1b) {
		r.say("THE CONTROL c1 DID NOT SHOW.  This phase's own output with the")
		r.cont("literal exclusion removed -- the plain sed, which rewrites")
		r.cont("\"[NULL]\", \"NULL\" and the E1507 message -- gives a binary")
		r.cont("IDENTICAL to the input's, so the cmp above is two numbers")
		r.cont("agreeing and proves nothing.  A test that cannot fail is not")
		r.cont("evidence (CLAUDE.md).")
		return harness.ErrReported
	}
	diffBytes := z23CmpL(ob, c1b)
	orod, crod := filepath.Join(tmp, "old.rodata"), filepath.Join(tmp, "c1.rodata")
	exec.Command("objcopy", "-O", "binary", "--only-section=.rodata", oldBin, orod).Run()
	exec.Command("objcopy", "-O", "binary", "--only-section=.rodata", filepath.Join(tmp, "c1"), crod).Run()
	if sizeOf(orod) <= 0 || sizeOf(crod) <= 0 {
		return stop("objcopy wrote an empty .rodata, and comparing two empty streams reports every pair of binaries identical (CLAUDE.md)")
	}
	rodataBytes := z23CmpL([]byte(readFile(orod)), []byte(readFile(crod)))
	if rodataBytes < 1000 {
		return stop("c1 differs in %d bytes of .rodata, and the three strings it rewrites are 84 characters between them -- expected over a thousand", rodataBytes)
	}
	so, _ := exec.Command("strings", "-a", filepath.Join(tmp, "c1")).Output()
	if !hasLine(so, "[nullptr]") {
		return stop("c1's .rodata does not contain '[nullptr]', so the control did not do the thing it is a control for")
	}
	if !bytes.Equal(ob, []byte(readFile(filepath.Join(tmp, "c2")))) {
		r.say("THE CONTROL c2 MOVED, AND IT IS DECLARED TO MOVE NOTHING.")
		r.cont("One vendored parameter reverted from `usize` to `size_t`")
		r.cont("must give the same bytes while the #includes are still at the")
		r.cont("top of the file: the two are THE SAME TYPE.  If it now moves")
		r.cont("something, this phase's account of its own evidence has to be")
		r.cont("rewritten rather than the number quietly updated.")
		return harness.ErrReported
	}
	r.say("AND IT CAN FAIL: this phase's own output with the literal exclusion removed -- the plain `sed 's/\\bNULL\\b/nullptr/g'`, which is the one mistake this phase can make -- differs from the input's binary in %d bytes, %d of them in .rodata, and `strings` finds '[nullptr]' where the editor's data said '[NULL]'.  That is CLAUDE.md's rule that the check for DATA is the strings, arriving on a phase nobody expected it on", diffBytes, rodataBytes)
	r.say("AND ONE CONTROL MOVES NOTHING, WHICH IS REPORTED RATHER THAN HIDDEN: one vendored `usize` reverted to `size_t` is byte-identical, because the #includes are still at the TOP and `size_t` is still declared above every line of the file.  The rename is not load-bearing YET; at phase 26, which moves them, the same control is three hard errors")
	return nil
}
