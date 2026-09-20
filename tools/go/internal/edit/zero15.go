package edit

import (
	"io"
	"os"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { registerArgs("zero15", Zero15) }

var z15Before = map[string]int{
	"tolower": 2, "toupper": 2, "towlower": 2, "towupper": 2,
	"isalnum": 2, "iscntrl": 1, "ispunct": 1,
	"isalpha": 3, "isdigit": 7, "isgraph": 1, "islower": 1, "isupper": 5,
	"iswupper": 1, "isspace": 0, "isprint": 0,
	"atoi": 7, "atol": 3, "qsort": 1, "bsearch": 4,
	"utf_convert": 4, "sort_strings": 3, "sort_compare": 1,
}

// z15Free are the nineteen musl_ names this phase defines.  This file is ONE
// namespace and a silent collision between a tentative definition and a vendored
// one is exactly what CLAUDE.md warns about, so each is required to be free.
var z15Free = []string{"musl_isdigit", "musl_isalpha", "musl_isupper", "musl_islower",
	"musl_isgraph", "musl_isspace", "musl_isalnum", "musl_iscntrl",
	"musl_ispunct", "musl_tolower", "musl_toupper", "musl_atoi",
	"musl_atol", "musl_bsearch", "musl_qsort", "musl_towupper",
	"musl_towlower", "musl_toUpper", "musl_toLower"}

// z15Rewrite is the sixteen names and the number of call sites each has BELOW
// the inserted block.
var z15Rewrite = []struct {
	name string
	want int
}{
	{"tolower", 2}, {"toupper", 2}, {"towlower", 2}, {"towupper", 2},
	{"isalnum", 2}, {"iscntrl", 1}, {"ispunct", 1},
	{"isalpha", 3}, {"isdigit", 7}, {"isgraph", 1}, {"islower", 1},
	{"isupper", 5},
	{"atoi", 7}, {"atol", 3}, {"qsort", 1}, {"bsearch", 4},
}

// z15Provided is everything <ctype.h> and <wctype.h> could still be providing.
var z15Provided = strings.Fields(
	"isalnum isalpha isblank iscntrl isdigit isgraph islower isprint " +
		"ispunct isspace isupper isxdigit isascii toascii tolower toupper " +
		"iswalnum iswalpha iswblank iswcntrl iswdigit iswgraph iswlower " +
		"iswprint iswpunct iswspace iswupper iswxdigit towlower towupper " +
		"towctrans wctrans wctype iswctype")

var z15Dead = regexp.MustCompile(`(?m)^ *return utf_is(?:upper|lower)\(c\);\n *if \(c >= 0x100\)$`)

// zCalls counts occurrences of `name` as a CALL, which is what a header
// provides.  NOT `\bname\b`: "isprint" is also the name of an option and lives
// in a string literal, so a word count says 1 on a file that calls it nowhere.
//
// The Python spells it `(?<![\w])name\s*\(`, and RE2 has no lookbehind, so the
// preceding byte is tested instead -- which is CLAUDE.md's own answer for
// `nobackup` and `noconv`, and is exact rather than an approximation of one.
func zCalls(t []byte, name string) int {
	n := 0
	for _, m := range zCallRe(name).FindAllIndex(t, -1) {
		if m[0] > 0 && isWordByte(t[m[0]-1]) {
			continue
		}
		n++
	}
	return n
}

func zCallRe(name string) *regexp.Regexp {
	return regexp.MustCompile(regexp.QuoteMeta(name) + `\s*\(`)
}

// Zero15 vendors the character classes, the two ato*, qsort and bsearch.
func Zero15(text []byte, w io.Writer, args []string) ([]byte, error) {
	p := ph{"vendor", w}
	if len(args) != 2 {
		return nil, p.die("usage: edit zero15 <file> <musl-ctype.txt> <musl-case.txt>")
	}
	var err error
	textEdit := func(t []byte, old, new, what string, n int) ([]byte, error) {
		k := strings.Count(string(t), old)
		if k != n {
			return nil, p.die("%s -- the text occurs %d times, expected %d: %s",
				what, k, n, cutil.PyRepr(zHead(old, 70)))
		}
		p.say(what)
		return []byte(strings.ReplaceAll(string(t), old, new)), nil
	}

	// ---- 0. the shape every anchor below was counted against ------------------
	for _, name := range sortedKeys(z15Before) {
		if k := zCalls(text, name); k != z15Before[name] {
			return nil, p.die("%s is called %d times, expected %d -- the anchors below were counted "+
				"against a different file", name, k, z15Before[name])
		}
	}
	p.say("eleven undefined symbols at 2 2 2 2 2 1 1 / 7 3 / 1 4 calls, the SIX macros " +
		"that produce no undefined symbol at all at 3 7 1 1 5 (isspace 0), and iswupper " +
		"at 1 -- the file the three anchors were counted against")

	for _, name := range z15Free {
		if regexp.MustCompile(`\b` + name + `\b`).Match(text) {
			return nil, p.die("%s already exists in the file", name)
		}
	}
	p.say("the nineteen musl_ names this phase defines are all free")

	// ---- THE INVARIANT, COMPUTED BEFORE ANYTHING IS INSERTED ------------------
	if k := len(z15Dead.FindAll(text, -1)); k != 2 {
		return nil, p.die("the two dead `if (c >= 0x100)` arms of vim_isupper/vim_islower are not "+
			"where this phase found them (%d)", k)
	}
	p.say("vim_isupper and vim_islower still open with `return utf_is*(c);` followed by an " +
		"unreachable `if (c >= 0x100)` -- which is the shape that makes iswupper a name " +
		"in the source and not a symbol in the object")

	// ---- A. the seventeen functions, after NGETTEXT ---------------------------
	blockB, err := os.ReadFile(args[0])
	if err != nil {
		return nil, p.die("%v", err)
	}
	block := string(blockB)
	// THE BLOCK JOINS PHASE 14'S RATHER THAN STARTING A SECOND ONE, so the anchor
	// is that JUNCTION -- the end of its last definition and the first enum --
	// and not a line of its own.
	const z15Tail = "    dest[18] = '\\0';\n    return 18;\n}\n"
	const z15Wall = "\nenum { BH_DIRTY = 1 };\n"
	if text, err = textEdit(text, z15Tail+z15Wall, z15Tail+block+z15Wall,
		"the seventeen functions go at the END OF PHASE 14's BLOCK, before the "+
			"enum wall -- one vendored block and not two -- defined before every "+
			"use, so only the two dead tow* mentions need a prototype", 1); err != nil {
		return nil, err
	}

	// ---- B. the two tables, beside vim's own ----------------------------------
	caseB, err := os.ReadFile(args[1])
	if err != nil {
		return nil, p.die("%v", err)
	}
	const z15ToUpperEnd = "        {0x1e922,0x1e943,1,-34}\n};\n"
	if text, err = textEdit(text, z15ToUpperEnd, z15ToUpperEnd+string(caseB),
		"musl's case mapping as 187 + 171 convertStruct rows, after vim's own "+
			"toUpper[] -- the same shape, the same size, and read by the "+
			"utf_convert() that is already declared above them", 1); err != nil {
		return nil, err
	}

	// ---- C. the dead statement ------------------------------------------------
	if text, err = textEdit(text, "            return iswupper(c);\n", "",
		"vim_isupper's `return iswupper(c);`, which cannot run and is "+
			"<wctype.h>'s last user besides the two this phase vendors -- deleting "+
			"it is byte-identical, measured with SOURCE_DATE_EPOCH=0", 1); err != nil {
		return nil, err
	}

	// ---- D. the call sites, counted, and only BELOW the block -----------------
	// The rewrites are applied to the text AFTER the inserted functions so that
	// the block's own bodies -- musl_ispunct calls musl_isalnum, musl_atoi calls
	// musl_isdigit -- are never themselves rewritten.  A file-wide regex would
	// have turned musl_tolower's body into musl_musl_tolower.
	cut := strings.Index(string(text), block) + len(block)
	head, body := string(text[:cut]), string(text[cut:])
	for _, r := range z15Rewrite {
		var idx [][]int
		for _, m := range zCallRe(r.name).FindAllStringIndex(body, -1) {
			if m[0] > 0 && isWordByte(body[m[0]-1]) {
				continue
			}
			idx = append(idx, m)
		}
		if len(idx) != r.want {
			return nil, p.die("%s is called %d times below the inserted block, expected %d",
				r.name, len(idx), r.want)
		}
		// ONE PASS over the original text, in order, because a span is an OFFSET
		// and every offset after a replacement is wrong -- CLAUDE.md's rule, and
		// the reason zero23 left five of 437 size_t behind when it was two.
		var out strings.Builder
		prev := 0
		for _, m := range idx {
			// THE WHOLE MATCH IS REPLACED, not prefixed.  The Python writes
			// `re.sub(r'name\s*\(', 'musl_name(')`, so a call written
			// `isupper (c)` loses its space; keeping the matched text and
			// prefixing it leaves `musl_isupper (c)`, which is the same program
			// and a different file -- measured, 6 lines of the tree.
			out.WriteString(body[prev:m[0]])
			out.WriteString("musl_" + r.name + "(")
			prev = m[1]
		}
		out.WriteString(body[prev:])
		body = out.String()
	}
	text = []byte(head + body)
	p.say("sixteen counted rewrites: tolower 2, toupper 2, towlower 2, towupper 2, " +
		"isalnum 2, iscntrl 1, ispunct 1, isalpha 3, isdigit 7, isgraph 1, islower 1, " +
		"isupper 5, atoi 7, atol 3, qsort 1, bsearch 4 -- 44 call sites, every one of " +
		"them BELOW the block, so no vendored body rewrites itself")

	// ---- what the sweep is handed, as a count rather than as trust ------------
	var left []string
	for _, n := range z15Provided {
		if zCalls(text, n) > 0 {
			left = append(left, n)
		}
	}
	if len(left) > 0 {
		return nil, p.die("<ctype.h>/<wctype.h> still has a user and phase 16 could not remove it: %s",
			strings.Join(left, " "))
	}
	for _, tn := range []string{"wint_t", "wctype_t", "wctrans_t"} {
		if regexp.MustCompile(`\b` + tn + `\b`).Match(text) {
			return nil, p.die("%s is still named, and it is <wctype.h>'s", tn)
		}
	}
	p.say("nothing <ctype.h> or <wctype.h> provides is called anywhere, and no wint_t, " +
		"wctype_t or wctrans_t is named -- which is the contract phase 16 removes the " +
		"two headers on, asserted here so that a miss fails THIS phase")
	if zCalls(text, "iswupper") > 0 || regexp.MustCompile(`\biswupper\b`).Match(text) {
		return nil, p.die("iswupper survives")
	}
	var directives, bad []string
	for _, l := range strings.Split(string(text), "\n") {
		if strings.HasPrefix(l, "#") {
			directives = append(directives, l)
			if !strings.HasPrefix(l, "#include <") {
				bad = append(bad, l)
			}
		}
	}
	if len(directives) != 18 || len(bad) > 0 {
		return nil, p.die("the directives are no longer 18 #includes of a system header: %d, %s",
			len(directives), strings.Join(bad, " "))
	}
	p.say("18 directives, every one an #include of a system header -- this phase adds no " +
		"preprocessor and removes none; the two it makes unnecessary are phase 16's")
	return text, nil
}
