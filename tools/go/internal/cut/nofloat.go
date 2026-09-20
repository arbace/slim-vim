package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

const nofloatRound = `                score = (fzy_score ==  INFINITY ) ? INT_MAX
                    : (int)(fzy_score * SCORE_SCALE + ((fzy_score < 0) ? -0.5 : 0.5));`

const nofloatOldRound = `                score = (fzy_score ==  INFINITY ) ? INT_MAX
                    : (fzy_score < 0) ? (int)ceil(fzy_score * SCORE_SCALE - 0.5)
                    : (int)floor(fzy_score * SCORE_SCALE + 0.5);`

const floatLabels = "            case 'f':\n            case 'F':\n" +
	"            case 'e':\n            case 'E':\n" +
	"            case 'g':\n            case 'G':\n"

var (
	// A printf conversion: % then flags, width, precision, then the letter.
	floatConv = regexp.MustCompile(`%[-+ #0']*[0-9*]*(?:\.[0-9*]*)?[fFeEgG]`)
	// A C string literal, escapes included.
	cLiteral = regexp.MustCompile(`"(?:[^"\\\n]|\\.)*"`)
	// Terminfo capability strings use % as an operator language of their own
	// -- %p1 pushes a parameter, %{1} a constant, %? %t %e %; are its
	// conditional.  `\033[?1006;1000%?%p1%{1}%=%th%el%;` is not a printf
	// format and its %e is an `else`.  Raw text is worse still:
	// `indent % get_sw_value(curbuf)` is C.
	terminfo     = regexp.MustCompile(`%[p{?;]|%t[^a-zA-Z]`)
	looseFormat  = regexp.MustCompile(`vim_v?snprintf[_a-z]*\([^,]*,[^,]*, *[A-Za-z_][\w>.\-]*[,)]`)
	libmCall     = regexp.MustCompile(`\b(?:ceil|floor|log10)\s*\(`)
	typeFloatEnd = regexp.MustCompile(`,\n    TYPE_FLOAT\n\};`)
)

var nofloatCuts = []struct{ what, pat string }{
	{"format_typeof's float arm",
		`(?m)^    case 'f':\n    case 'F':\n    case 'e':\n    case 'E':\n` +
			`    case 'g':\n    case 'G':\n        return TYPE_FLOAT;\n\n?`},
	{"the argument walker's six labels",
		`(?m)^[ \t]*case 'f':\n[ \t]*case 'F':\n[ \t]*case 'e':\n` +
			`[ \t]*case 'E':\n[ \t]*case 'g':\n[ \t]*case 'G':\n`},
	{"format_typename's float arm",
		`(?m)^[ \t]*case TYPE_FLOAT:\n[ \t]*return typename_float;\n`},
	{"the va_arg walker's float arm",
		`(?m)^[ \t]*case TYPE_FLOAT:\n[ \t]*va_arg\(\*ap, double\);\n[ \t]*break;\n\n?`},
}

// checkNoFloatFormats refuses to cut unless nothing can reach the branch being
// cut.
//
// SCANNING EVERY LITERAL IS THE COMPLETE CHECK, and that is worth saying
// because twelve call sites pass a format that is not a literal.  None of them
// CONSTRUCTS one: smsg() and semsg() forward the format parameter they were
// given, vim_snprintf() forwards to vim_vsnprintf(), and the three remaining
// locals are assigned from literals a few lines above.  So every format that
// can reach the branch originates as a literal in this file, and every literal
// in this file has just been read.
func checkNoFloatFormats(text []byte, w io.Writer) error {
	var bad []string
	lits := cLiteral.FindAllIndex(text, -1)
	for _, m := range lits {
		lit := text[m[0]:m[1]]
		if terminfo.Match(lit) {
			continue
		}
		if floatConv.Match(lit) {
			line := bytes.Count(text[:m[0]], []byte{'\n'}) + 1
			s := string(lit)
			if len(s) > 70 {
				s = s[:70]
			}
			bad = append(bad, fmt.Sprintf("%d: %s", line, s))
		}
	}
	if len(bad) > 0 {
		show := bad
		if len(show) > 5 {
			show = show[:5]
		}
		return fmt.Errorf("nofloat: %d string literals carry a float conversion, so the "+
			"%%f branch IS reachable and must not be removed:\n    %s",
			len(bad), strings.Join(show, "\n    "))
	}
	fmt.Fprintf(w, "  nofloat      no float conversion in any of %d string literals; the "+
		"%d forwarded formats all originate in one\n",
		len(lits), len(looseFormat.FindAll(text, -1)))
	return nil
}

// NoFloat removes the float conversion nothing can reach, and the libm calls
// that were the only other floating point in the file.
func NoFloat(text []byte, w io.Writer) ([]byte, error) {
	if err := checkNoFloatFormats(text, w); err != nil {
		return nil, err
	}

	if !bytes.Contains(text, []byte(nofloatOldRound)) {
		return nil, fmt.Errorf("nofloat: the fuzzy matcher's rounding is not where this expects")
	}
	text = bytes.Replace(text, []byte(nofloatOldRound), []byte(nofloatRound), 1)
	fmt.Fprintln(w, "  nofloat      ceil and floor: a conversion truncates toward zero, "+
		"which is both of them")

	blanked := cutil.Blank(text)
	k := bytes.Index(text, []byte(floatLabels+"                {\n"))
	if k < 0 {
		return nil, fmt.Errorf("nofloat: the float conversion case is not where this expects")
	}
	o := k + len(floatLabels) + bytes.IndexByte(blanked[k+len(floatLabels):], '{')
	c := cutil.Match(blanked, o)
	if c < 0 {
		return nil, fmt.Errorf("nofloat: the float conversion case is unbalanced")
	}
	if !bytes.Contains(text[k:c], []byte("log10")) {
		return nil, fmt.Errorf("nofloat: the float conversion case is not where this expects")
	}
	end := c + bytes.IndexByte(text[c:], '\n') + 1
	if end < len(text) && text[end] == '\n' {
		end++
	}
	fmt.Fprintf(w, "  nofloat      the %%f conversion, %d lines nothing can reach\n",
		bytes.Count(text[k:end], []byte{'\n'}))
	var buf []byte
	buf = append(buf, text[:k]...)
	text = append(buf, text[end:]...)

	for _, c := range nofloatCuts {
		re := regexp.MustCompile(c.pat)
		var hit bool
		text, hit = replaceFirst(re, text, "")
		if !hit {
			return nil, fmt.Errorf("nofloat: %s -- expected 1, matched 0", c.what)
		}
	}

	// TYPE_FLOAT is the LAST enumerator, so removing it renumbers nothing --
	// checked, because several enums in this file index a parallel table.
	var hit bool
	if text, hit = replaceFirst(typeFloatEnd, text, "\n};"); !hit {
		return nil, fmt.Errorf("nofloat: TYPE_FLOAT is not the last enumerator any more")
	}
	fmt.Fprintln(w, "  nofloat      TYPE_FLOAT and its three arms")

	fmt.Fprintf(w, "  nofloat      %d libm calls left\n", len(libmCall.FindAll(text, -1)))
	return text, nil
}
