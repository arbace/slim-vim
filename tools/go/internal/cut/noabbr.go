package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

var abbrFolds = []struct{ what, pattern string }{
	{"insert mode: ESC expanding an abbreviation first",
		`(?m)^[ \t]*if \(echeck_abbr\(ESC \+ ABBR_OFF\)\)$`},
	{"insert mode: CTRL-O expanding an abbreviation first",
		`(?m)^[ \t]*if \(echeck_abbr\(Ctrl_O \+ ABBR_OFF\)\)$`},
	{"insert mode: CTRL-L under 'insertmode'",
		`(?m)^[ \t]*if \(echeck_abbr\(Ctrl_L \+ ABBR_OFF\)\)$`},
	{"insert mode: Tab expanding an abbreviation first",
		`(?m)^[ \t]*if \(echeck_abbr\(TAB \+ ABBR_OFF\)\)$`},
	{"insert mode: Enter expanding an abbreviation first",
		`(?m)^[ \t]*if \(echeck_abbr\(c \+ ABBR_OFF\)\)$`},
	{"the command line: a special key expanding an abbreviation",
		`(?m)^[ \t]*if \(ccheck_abbr\(c \+ ABBR_OFF\)\)$`},
}

var abbrLiteral = []struct{ what, old, new string }{
	{"insert mode: a non-word character inserting unless an abbreviation took it",
		"if (vim_iswordc(c) || (!echeck_abbr((has_mbyte && c >= 0x100) ? (c + ABBR_OFF) : c) && c != Ctrl_RSB))",
		"if (vim_iswordc(c) || c != Ctrl_RSB)"},
	{"the command line: a non-word character expanding an abbreviation",
		"(ccheck_abbr((has_mbyte && c >= 0x100) ? (c + ABBR_OFF) : c) || c == Ctrl_RSB)",
		"c == Ctrl_RSB"},
}

var (
	abbrCall  = regexp.MustCompile(`\b[ec]?check_abbr\(`)
	abbrProto = regexp.MustCompile(`^static\s+int\s+[ec]?check_abbr\(`)
)

// NoAbbr takes away every place an abbreviation could still be expanded.
//
// The last act is the one that matters: nothing may still ASK.  The two
// wrappers must have no caller at all and check_abbr() none outside them --
// which the sweep takes, so a call left INSIDE one of them is not a caller,
// and that is why the scan excludes the three definitions' own spans rather
// than counting mentions.
func NoAbbr(text []byte, w io.Writer) ([]byte, error) {
	for _, f := range abbrFolds {
		out, err := cutil.FoldNever(text, f.pattern, 1)
		if err != nil {
			return nil, fmt.Errorf("noabbr: %s -- %v", f.what, err)
		}
		text = out
		fmt.Fprintf(w, "  noabbr       %s\n", f.what)
	}
	for _, l := range abbrLiteral {
		n := bytes.Count(text, []byte(l.old))
		if n != 1 {
			return nil, fmt.Errorf("noabbr: %s -- occurs %d times, not once", l.what, n)
		}
		text = bytes.ReplaceAll(text, []byte(l.old), []byte(l.new))
		fmt.Fprintf(w, "  noabbr       %s\n", l.what)
	}

	blanked := cutil.Blank(text)
	type span struct{ a, z int }
	var spans []span
	for _, n := range []string{"echeck_abbr", "ccheck_abbr", "check_abbr"} {
		if a, z, ok := cutil.FindDefinition(text, blanked, n); ok {
			spans = append(spans, span{a, z})
		}
	}
	inside := func(pos int) bool {
		for _, s := range spans {
			if s.a <= pos && pos < s.z {
				return true
			}
		}
		return false
	}
	lineAt := func(pos int) []byte {
		a := bytes.LastIndexByte(text[:pos], '\n') + 1
		z := bytes.IndexByte(text[pos:], '\n')
		if z < 0 {
			return text[a:]
		}
		return text[a : pos+z]
	}
	var still []string
	for _, m := range abbrCall.FindAllIndex(text, -1) {
		if inside(m[0]) {
			continue
		}
		a := bytes.LastIndexByte(text[:m[0]], '\n') + 1
		if abbrProto.Match(text[a:]) {
			continue
		}
		line := strings.TrimSpace(string(lineAt(m[0])))
		if len(line) > 100 {
			line = line[:100]
		}
		still = append(still, line)
	}
	if len(still) > 0 {
		return nil, fmt.Errorf("noabbr: still asked at:\n    %s", strings.Join(still, "\n    "))
	}

	fmt.Fprintln(w, "  noabbr       nothing asks whether an abbreviation applies")
	return text, nil
}
