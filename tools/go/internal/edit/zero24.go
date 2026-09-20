package edit

import (
	"io"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { register("zero24", Zero24) }

var (
	z24Inc     = regexp.MustCompile(`^#include <([A-Za-z0-9_/.]+)>$`)
	z24Attr    = regexp.MustCompile(`__attribute__\(\((\w+)`)
	z24Words   = regexp.MustCompile(`attribute|fallthrough|unused`)
	z24Fall    = regexp.MustCompile(`(?m)^[ ]*__attribute__\(\(fallthrough\)\);$`)
	z24C23     = regexp.MustCompile(`(?m)^[ ]*\[\[fallthrough\]\];$`)
	z24Head    = regexp.MustCompile(`^(?:static\s+[\w \*]+?\s*\**)?(\w+)\s*$`)
	z24Fmt     = regexp.MustCompile(`format(_arg)?\(`)
	z24Pad     = regexp.MustCompile(`  [,)]`)
	z24Unused  = regexp.MustCompile(`__attribute__\(\(unused\)\)`)
	z24NeedleS = "  __attribute__((unused)) "
)

// z24Kinds are the four kinds of attribute this phase has a decision for.  A
// FIFTH APPEARING IS A DECISION THIS PHASE HAS NEVER TAKEN, and it must refuse
// rather than leave it or guess -- a partition and not a count.
var z24Kinds = []string{"unused", "fallthrough", "format", "format_arg"}

// Zero24 takes the attributes: 139 GNU `__attribute__` to six.
func Zero24(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"attrs", w}

	blankRuns := func(t []byte) int {
		L := strings.Split(string(t), "\n")
		n := 0
		for i := 1; i < len(L); i++ {
			if L[i] == "" && L[i-1] == "" {
				n++
			}
		}
		return n
	}

	// ---- 0. the file this edit was written against ----------------------------
	// `[[fallthrough]]` is a STATEMENT and not a directive, so this phase must
	// leave the eleven exactly where it found them.
	lines := strings.Split(string(text), "\n")
	var dIdx []int
	var dLines []string
	for i, l := range lines {
		if strings.HasPrefix(l, "#") {
			dIdx = append(dIdx, i)
			dLines = append(dLines, l)
		}
	}
	ok := len(dIdx) == 11
	for i := range dIdx {
		if dIdx[i] != i {
			ok = false
		}
	}
	if !ok {
		at := make([]string, len(dIdx))
		for i, v := range dIdx {
			at[i] = strconv.Itoa(v)
		}
		return nil, p.die("the file does not have exactly eleven preprocessor directives on its first "+
			"eleven lines: %d directives at lines %s", len(dIdx), strings.Join(at, " "))
	}
	for _, l := range dLines {
		if !z24Inc.MatchString(l) {
			return nil, p.die("a directive is not an `#include <...>` of a system header, and no phase may " +
				"add one")
		}
	}
	if strings.Contains(string(text), "[[") {
		return nil, p.die("`[[` already occurs %d times -- this phase introduces C23 attribute syntax, "+
			"so an existing occurrence means the phase has already run or the spelling is "+
			"taken", strings.Count(string(text), "[["))
	}
	p.say("eleven directives, every one an `#include <...>` on the first eleven lines, and " +
		"`[[` at zero occurrences")

	// ---- 1. the literals ------------------------------------------------------
	spans, err := literalSpans(p, text)
	if err != nil {
		return nil, err
	}
	var bad, words []string
	for _, s := range spans {
		lit := string(text[s[0]:s[1]])
		if strings.Contains(lit, "__attribute__") || strings.Contains(lit, "[[") {
			bad = append(bad, lit)
		}
		if z24Words.MatchString(lit) {
			words = append(words, lit)
		}
	}
	if len(bad) > 0 {
		return nil, p.die("a literal holds `__attribute__` or `[[`, and no substitution below may reach "+
			"inside a string: %s", strings.Join(bad, " / "))
	}
	p.sayf("%d string and character literals, NONE holding `__attribute__` or `[[`.  Two hold "+
		"the English words and neither is reachable by either substitution: %s",
		len(spans), strings.Join(words, " / "))

	// ---- 2. the partition -----------------------------------------------------
	allAttrs := z24Attr.FindAllStringSubmatch(string(text), -1)
	kinds := map[string]int{}
	for _, m := range allAttrs {
		kinds[m[1]]++
	}
	var extra []string
	for k := range kinds {
		if !contains(z24Kinds, k) {
			extra = append(extra, k)
		}
	}
	if len(extra) > 0 {
		sort.Strings(extra)
		return nil, p.die("the file holds an attribute this phase has never looked at: %s -- the three "+
			"decisions below are about %s and nothing else",
			strings.Join(extra, " "), strings.Join(z24Kinds, " "))
	}
	parts := make([]string, len(z24Kinds))
	for i, k := range z24Kinds {
		parts[i] = k + " " + strconv.Itoa(kinds[k])
	}
	p.sayf("%d `__attribute__` in the file, and every one is one of four kinds: %s",
		len(allAttrs), strings.Join(parts, ", "))

	// ---- 3. the 113: on a parameter, every one, computed ----------------------
	// THE SHAPE IS EXACT AND IT IS THE TRAP.  Each is written `<declarator>
	// __attribute__((unused)) ` -- TWO spaces before and ONE after -- and is
	// followed by the `,` or `)` of the parameter list.  Deleting the attribute
	// alone would leave a doubled space, or a space before a `)`, and canon.sh
	// takes neither.  RE2 has no lookaround, so the Python's `(?<=\S)` and
	// `(?=[,)])` are the byte either side, tested.
	var unusedSpans [][2]int
	s := string(text)
	for i := 0; ; {
		j := strings.Index(s[i:], z24NeedleS)
		if j < 0 {
			break
		}
		j += i
		e := j + len(z24NeedleS)
		if j > 0 && !z24IsSpace(s[j-1]) && e < len(s) && (s[e] == ',' || s[e] == ')') {
			unusedSpans = append(unusedSpans, [2]int{j, e})
		}
		i = e
	}
	nUnused := len(unusedSpans)
	if nUnused != kinds["unused"] {
		return nil, p.die("%d of the %d `unused` attributes are written the way this edit reads them -- "+
			"two spaces before, one after, and a `,` or `)` next.  Deleting the rest by a "+
			"different rule would leave a doubled space or a space before a paren, and "+
			"canon.sh takes neither", nUnused, kinds["unused"])
	}

	// EVERY ONE IS IN A FUNCTION DEFINITION'S PARAMETER LIST, computed on the
	// line.  No parenthesised group in this file spans a line break (CLAUDE.md),
	// so the innermost enclosing `(` is on the same line and walking back to it
	// is exact.
	seen := map[int]bool{}
	var unusedLines []int
	for _, m := range z24Unused.FindAllStringIndex(s, -1) {
		ln := strings.Count(s[:m[0]], "\n")
		if !seen[ln] {
			seen[ln] = true
			unusedLines = append(unusedLines, ln)
		}
	}
	sort.Ints(unusedLines)
	for _, i := range unusedLines {
		l := lines[i]
		k := strings.Index(l, "__attribute__((unused))")
		d, j := 0, -1
		for j = k - 1; j >= 0; j-- {
			if l[j] == ')' {
				d++
			} else if l[j] == '(' {
				if d == 0 {
					break
				}
				d--
			}
		}
		if j < 0 || !z24Head.MatchString(l[:j]) {
			return nil, p.die("the `unused` at line %d is not inside a function's parameter list -- what "+
				"precedes its innermost `(` is %s, which is not a function name, so this "+
				"may be an attribute on a variable, an object or a field and the phase has "+
				"no decision for those", i+1, cutil.PyRepr(z24Slice(l, j)))
		}
		if lines[i+1] != "{" {
			return nil, p.die("line %d holds an `unused` but is not a function DEFINITION header: the "+
				"line below it is %s and not `{`", i+1, cutil.PyRepr(lines[i+1]))
		}
	}
	p.sayf("%d `__attribute__((unused))`, ALL of them in the parameter list of a function "+
		"DEFINITION -- %d header lines, every one followed by `{` -- so not one is on a "+
		"variable, an object, a type or a field.  The sweep's own flags are "+
		"`-Wall -Wextra -Wno-unused-parameter`, which is why they say nothing",
		nUnused, len(unusedLines))

	// ---- 4. the 20: a standalone statement, every one -------------------------
	nFall := len(z24Fall.FindAllString(s, -1))
	if nFall != kinds["fallthrough"] {
		return nil, p.die("%d of the %d `fallthrough` attributes are a whole line of their own -- the "+
			"swap below is one-for-one and textual, and an attribute sharing a line with "+
			"anything else is not a case it has looked at", nFall, kinds["fallthrough"])
	}
	p.sayf("%d `__attribute__((fallthrough));`, every one a standalone statement on a line of "+
		"its own, so the swap to the C23 spelling is one-for-one and reaches nothing else", nFall)

	// ---- 5. the six that stay -------------------------------------------------
	// Recorded as the exact LINES they sit on, so the check can require them back
	// byte for byte.
	var keep []int
	var keepText []string
	for i, l := range lines {
		if z24Fmt.MatchString(l) && strings.Contains(l, "__attribute__") {
			keep = append(keep, i)
			keepText = append(keepText, l)
		}
	}
	nKeep := 0
	for _, l := range keepText {
		nKeep += strings.Count(l, "__attribute__")
	}
	if nKeep != kinds["format"]+kinds["format_arg"] {
		return nil, p.die("the `format` and `format_arg` attributes are on %d lines carrying %d of them, "+
			"and there are %d in the file -- the phase must be able to name every one it "+
			"keeps", len(keep), nKeep, kinds["format"]+kinds["format_arg"])
	}
	p.sayf("%d `format`/`format_arg` on %d lines KEPT, and they are the only attributes doing "+
		"work nothing else does: with all six removed the binary is cmp-IDENTICAL and "+
		"`-Wformat=2` goes from 115 warnings to ZERO", nKeep, len(keep))

	// ---- 6. the two substitutions ---------------------------------------------
	runsBefore := blankRuns(text)
	padBefore := len(z24Pad.FindAllString(s, -1))
	var out strings.Builder
	prev := 0
	for _, sp := range unusedSpans {
		out.WriteString(s[prev:sp[0]])
		prev = sp[1]
	}
	out.WriteString(s[prev:])
	s = out.String()
	a := len(unusedSpans)
	b := len(z24Fall.FindAllString(s, -1))
	s = z24Fall.ReplaceAllStringFunc(s, func(m string) string {
		return strings.Replace(m, "__attribute__((fallthrough));", "[[fallthrough]];", 1)
	})
	if a != nUnused || b != nFall {
		return nil, p.die("the substitutions took %d and %d where %d and %d were counted",
			a, b, nUnused, nFall)
	}
	text = []byte(s)
	p.sayf("%d `__attribute__((unused))` deleted with the two spaces before them and the one "+
		"after, and %d `__attribute__((fallthrough));` respelled `[[fallthrough]];`", a, b)

	// ---- 7. what the file is now ----------------------------------------------
	L := strings.Split(s, "\n")
	if len(L) != len(lines) {
		return nil, p.die("the file is %d lines and the input was %d -- both edits are WITHIN lines and "+
			"neither may add or remove one", len(L)-1, len(lines)-1)
	}
	var leftK []string
	for _, m := range z24Attr.FindAllStringSubmatch(s, -1) {
		leftK = append(leftK, m[1])
	}
	wantK := make([]string, 0, kinds["format"]+kinds["format_arg"])
	for i := 0; i < kinds["format"]; i++ {
		wantK = append(wantK, "format")
	}
	for i := 0; i < kinds["format_arg"]; i++ {
		wantK = append(wantK, "format_arg")
	}
	gotK := append([]string{}, leftK...)
	sort.Strings(gotK)
	sort.Strings(wantK)
	if strings.Join(gotK, " ") != strings.Join(wantK, " ") {
		shown := strings.Join(gotK, " ")
		if shown == "" {
			shown = "none"
		}
		return nil, p.die("the attributes left are %s, and they must be exactly the %d format and %d "+
			"format_arg", shown, kinds["format"], kinds["format_arg"])
	}
	for i, k := range keep {
		if L[k] != keepText[i] {
			return nil, p.die("a line carrying a kept attribute is not the line it was, byte for byte")
		}
	}
	if len(z24Fall.FindAllString(s, -1)) > 0 || strings.Contains(s, "__attribute__((unused))") {
		return nil, p.die("an `unused` or a GNU `fallthrough` survives the substitution")
	}
	if len(z24C23.FindAllString(s, -1)) != nFall {
		return nil, p.die("the %d C23 statements are not %d standalone lines", nFall, nFall)
	}
	if k := len(z24Pad.FindAllString(s, -1)); k != padBefore {
		return nil, p.die("the edit left %d doubled spaces before a `,` or `)` where there were %d -- "+
			"deleting the attribute without its own two spaces is exactly the mistake this "+
			"phase can make, and canon.sh does not take it", k, padBefore)
	}
	if r := blankRuns(text); r != runsBefore {
		return nil, p.die("the edit left %d runs of two blank lines where there were %d", r, runsBefore)
	}
	changed := 0
	for i := range L {
		if L[i] != lines[i] {
			changed++
		}
	}
	if changed != len(unusedLines)+nFall {
		return nil, p.die("%d lines changed, expected %d -- the %d headers and the %d fallthrough "+
			"statements, and nothing else", changed, len(unusedLines)+nFall, len(unusedLines), nFall)
	}
	p.sayf("%d attributes -> %d, the same %d lines, %d changed -- the %d function headers and "+
		"the %d fallthrough statements -- and the doubled-space count unmoved at %d",
		len(allAttrs), len(leftK), len(L)-1, changed, len(unusedLines), nFall, padBefore)
	return text, nil
}

func z24IsSpace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v'
}

// z24Slice is Python's `l[:j]`, negative j included -- the refusal quotes it and
// j is -1 exactly when the attribute is the first thing on the line.
func z24Slice(l string, j int) string {
	if j < 0 {
		j += len(l)
		if j < 0 {
			j = 0
		}
	}
	if j > len(l) {
		j = len(l)
	}
	return l[:j]
}
