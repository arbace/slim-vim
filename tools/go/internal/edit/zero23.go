package edit

import (
	"bytes"
	"io"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { phases["zero23"] = Zero23 }

var (
	zero23Inc     = regexp.MustCompile(`^#include <([A-Za-z0-9_/.]+)>$`)
	zero23Null    = regexp.MustCompile(`\bNULL\b`)
	zero23SizeT   = regexp.MustCompile(`\bsize_t\b`)
	zero23Both    = regexp.MustCompile(`\b(NULL|size_t)\b`)
	zero23Decl    = regexp.MustCompile(`^(\*\s*)*[A-Za-z_,)]`)
	zero23VoidPtr = regexp.MustCompile(`\(void \*\)nullptr\b`)
	zero23Intro   = regexp.MustCompile(`(?m)^[^\n]*\btypedef\b[^\n]*\busize\b[^\n]*$`)
)

const zero23Typedef = "typedef typeof(sizeof(0)) usize;"
const zero23Anchor = "#include <termios.h>\n\n"

// Zero23 gives the core two names the language supplies instead of a header:
// NULL becomes nullptr and size_t becomes usize.
func Zero23(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"language", w}

	// ---- 0. the file this edit was written against -----------------------
	// ELEVEN DIRECTIVES on the first eleven lines: phase 21 left that, and
	// this phase adds a line directly below them, so it must know exactly
	// where they end.
	if err := zero23Directives(p, text, 11, "the file does not have exactly eleven preprocessor directives on its first "+
		"eleven lines"); err != nil {
		return nil, err
	}
	for _, name := range []string{"usize", "nullptr"} {
		if k := p.mentions(text, name); k != 0 {
			return nil, p.die("`%s` already occurs %d times -- this phase introduces it, so an existing "+
				"mention means the phase has already run or the name is taken", name, k)
		}
	}
	p.say("eleven directives, every one an `#include <...>` on the first eleven lines, and " +
		"`usize` and `nullptr` at zero mentions")

	// ---- 1. the literals, which are the one thing here that can go wrong -
	spans, err := literalSpans(p, text)
	if err != nil {
		return nil, err
	}
	starts := make([]int, len(spans))
	for i, s := range spans {
		starts[i] = s[0]
	}
	inLiteral := func(pos int) bool {
		k := sort.SearchInts(starts, pos+1) - 1
		return k >= 0 && spans[k][0] <= pos && pos < spans[k][1]
	}

	// THE THREE, NAMED, because the phase must be able to say afterwards
	// that they are UNCHANGED -- and because a fourth appearing is a fact
	// worth refusing on: it would be a message this phase has never seen.
	wantLits := []string{
		`"E1507: Internal error: ap_types or ap_types[idx] is NULL: %d: %s"`,
		`"[NULL]"`,
		`"NULL"`,
	}
	var holding []string
	for _, s := range spans {
		if zero23Null.Match(text[s[0]:s[1]]) {
			holding = append(holding, string(text[s[0]:s[1]]))
		}
	}
	sortedHolding := append([]string(nil), holding...)
	sort.Strings(sortedHolding)
	sortedWant := append([]string(nil), wantLits...)
	sort.Strings(sortedWant)
	if strings.Join(sortedHolding, "\x00") != strings.Join(sortedWant, "\x00") {
		j := strings.Join(sortedHolding, " / ")
		if j == "" {
			j = "none"
		}
		return nil, p.die("the literals containing `NULL` are not the three this phase knows about: %s", j)
	}
	for _, s := range spans {
		if zero23SizeT.Match(text[s[0]:s[1]]) {
			return nil, p.die("a literal contains `size_t`, which no literal in this file ever has")
		}
	}
	p.sayf("%d string and character literals, THREE of which contain `NULL` -- the E1507 "+
		"message, \"[NULL]\" and \"NULL\" -- and none of which contains `size_t`.  A line-wise "+
		"sed rewrites all three and moves 1,598 bytes of the binary", len(spans))

	// ---- 2. every `size_t` is in a position a typedef serves -------------
	// A PARTITION AND NOT A COUNT: casts and declarations must cover every
	// occurrence with nothing left over.  A leftover is a use that is not a
	// type name -- a case label, an array bound, a `sizeof(size_t)` -- which
	// a typedef could not serve.
	cast, decl := 0, 0
	for _, loc := range zero23SizeT.FindAllIndex(text, -1) {
		after := bytes.TrimLeft(text[loc[1]:], " \t\n\r\v\f")
		before := bytes.TrimRight(text[:loc[0]], " \t\n\r\v\f")
		switch {
		case bytes.HasSuffix(before, []byte("(")) && bytes.HasPrefix(after, []byte(")")):
			cast++
		case zero23Decl.Match(after):
			decl++
		default:
			lo := loc[0] - 30
			if lo < 0 {
				lo = 0
			}
			hi := loc[1] + 30
			if hi > len(text) {
				hi = len(text)
			}
			return nil, p.die("`size_t` at line %d is neither a cast nor a declaration, so it is a "+
				"position a typedef may not serve: %s",
				bytes.Count(text[:loc[0]], []byte{'\n'})+1, cutil.PyRepr(string(text[lo:hi])))
		}
	}
	p.sayf("%d mentions of `size_t`, ALL of them type-name positions: %d casts and %d "+
		"declarations, and nothing left over", cast+decl, cast, decl)

	// ---- 3. the substitution: one pass, outside literals -----------------
	// ONE PASS OVER THE ORIGINAL TEXT, for both names.  Two passes would
	// index spans computed on the first pass's OUTPUT, and measured, that
	// leaves five of the 437 `size_t` behind -- in a file that still compiles
	// and whose binary is still identical.
	runsBefore := p.blankRuns(text)
	repl := map[string]string{"NULL": "nullptr", "size_t": "usize"}
	count := map[string]int{}
	var out []byte
	last := 0
	for _, loc := range zero23Both.FindAllIndex(text, -1) {
		if inLiteral(loc[0]) {
			continue
		}
		name := string(text[loc[0]:loc[1]])
		out = append(out, text[last:loc[0]]...)
		out = append(out, repl[name]...)
		last = loc[1]
		count[name]++
	}
	out = append(out, text[last:]...)
	text = out
	p.sayf("`NULL` -> `nullptr` at %d sites and `size_t` -> `usize` at %d, in one pass and "+
		"outside every literal", count["NULL"], count["size_t"])

	// ---- 4. the cast the hazard used to need -----------------------------
	nCast := len(zero23VoidPtr.FindAll(text, -1))
	if nCast == 0 {
		return nil, p.die("no `(void *)NULL` site was found, and the phase states there are thirty -- the " +
			"convention that made the untyped spelling survivable is not written the way " +
			"this edit reads it")
	}
	text = zero23VoidPtr.ReplaceAll(text, []byte("nullptr"))
	p.sayf("%d `(void *)nullptr` -> `nullptr`: the cast existed for the variadic hazard, and "+
		"`nullptr` is typed, so it says nothing a reader needs", nCast)

	// ---- 5. the one new line ---------------------------------------------
	// DIRECTLY BELOW THE ELEVEN INCLUDES, so that when phase 27 moves them to
	// the bottom the typedef is the first line of the core.  A TYPEDEF and
	// not a `static` anything: `usize` is a type name, and every one of its
	// uses is a type-name position.
	if k := bytes.Count(text, []byte(zero23Anchor)); k != 1 {
		return nil, p.die("the last `#include` is not followed by exactly one blank line, so there is no " +
			"unambiguous place for the typedef")
	}
	text = bytes.Replace(text, []byte(zero23Anchor),
		[]byte(zero23Anchor+zero23Typedef+"\n\n"), 1)

	// ---- 6. what the file is now -----------------------------------------
	if err := zero23Directives(p, text, 11, "the eleven directives are no longer the first eleven lines"); err != nil {
		return nil, p.die("the eleven directives are no longer the first eleven lines")
	}
	lines := bytes.Split(text, []byte{'\n'})
	if len(lines) < 13 || string(lines[12]) != zero23Typedef {
		got := ""
		if len(lines) > 12 {
			got = string(lines[12])
		}
		return nil, p.die("the typedef did not land on line 13, below the includes and their blank: %s",
			cutil.PyRepr(got))
	}
	if bytes.Count(text, []byte(zero23Typedef+"\n")) != 1 {
		return nil, p.die("the typedef is not in the file exactly once")
	}
	for _, c := range []struct {
		name string
		want int
	}{{"NULL", 3}, {"size_t", 0}} {
		if k := p.mentions(text, c.name); k != c.want {
			return nil, p.die("`%s` has %d mentions after the cut, expected %d", c.name, k, c.want)
		}
	}
	after, err := literalSpans(p, text)
	if err != nil {
		return nil, err
	}
	var stillHolding []string
	for _, s := range after {
		if zero23Null.Match(text[s[0]:s[1]]) {
			stillHolding = append(stillHolding, string(text[s[0]:s[1]]))
		}
	}
	if strings.Join(stillHolding, "\x00") != strings.Join(holding, "\x00") {
		return nil, p.die("the three literals holding `NULL` are not the three they were")
	}
	intro := zero23Intro.FindAllString(string(text), -1)
	if len(intro) != 1 || intro[0] != zero23Typedef {
		j := strings.Join(intro, " / ")
		if j == "" {
			j = "nothing"
		}
		return nil, p.die("`usize` is introduced by something other than exactly one typedef: %s -- it is "+
			"a TYPE NAME and not a static object, and every one of its uses is a type-name "+
			"position", j)
	}
	if r := p.blankRuns(text); r != runsBefore {
		return nil, p.die("the edit left %d runs of two blank lines where there were %d", r, runsBefore)
	}
	p.sayf("the three `NULL` literals are the only `NULL` left, `size_t` is at zero, `usize` "+
		"is a typedef on line 13 and %d runs of two blank lines, exactly as before",
		p.blankRuns(text))
	return text, nil
}

// zero23Directives requires exactly n directives on the first n lines, each an
// `#include <...>` of a system header.
func zero23Directives(p ph, text []byte, n int, msg string) error {
	lines := bytes.Split(text, []byte{'\n'})
	var idx []int
	var at []string
	for i, l := range lines {
		if bytes.HasPrefix(l, []byte("#")) {
			idx = append(idx, i)
			at = append(at, strconv.Itoa(i))
		}
	}
	bad := len(idx) != n
	for k, i := range idx {
		if i != k {
			bad = true
		}
	}
	if bad {
		return p.die("%s: %d directives at lines %s", msg, len(idx), strings.Join(at, " "))
	}
	for _, i := range idx {
		if !zero23Inc.Match(lines[i]) {
			return p.die("a directive is not an `#include <...>` of a system header, and no phase may " +
				"add one")
		}
	}
	return nil
}
