package cut

import (
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// replaceFirst rewrites the FIRST match only, expanding $1 in repl.
//
// Python's re.subn(..., count=1) replaces one occurrence; Go's ReplaceAll
// replaces every one.  A cutter whose pattern matched twice would quietly take
// a second construct somewhere else in the file, which is the difference
// between a cut and a guess -- so this is the shape to reach for whenever the
// Python passed a count.
func replaceFirst(re *regexp.Regexp, text []byte, repl string) ([]byte, bool) {
	loc := re.FindSubmatchIndex(text)
	if loc == nil {
		return text, false
	}
	out := make([]byte, 0, len(text))
	out = append(out, text[:loc[0]]...)
	out = re.Expand(out, []byte(repl), text, loc)
	return append(out, text[loc[1]:]...), true
}

var notermEdits = []struct{ what, pat, repl string }{
	{"$TERM choosing the capability table",
		`(?m)[ \t]*if \(term == NULL\)\n[ \t]*\{\n` +
			`[ \t]*term =  \(char_u \*\)getenv\(\(char \*\)\(\(char_u \*\)"TERM"\)\) ;\n[ \t]*\}\n`,
		""},
	{"the fallback, which becomes the only path and must keep the colours",
		`(?m)([ \t]*if \(term == NULL \|\| \*term == NUL\)\n[ \t]*\{\n[ \t]*term =  \(char_u \*\))` +
			`"xterm" ;\n`, `${1}"xterm-256color" ;` + "\n"},
	{"$COLORS overriding the table's colour count",
		`(?m)[ \t]*\{\n[ \t]*env_colors =  \(char_u \*\)getenv\(\(char \*\)\(\(char_u \*\)"COLORS"\)\) ;\n` +
			`(?:[^\n]*\n)*?^[ \t]{4}\}\n`, ""},
	{"$COLORS suppressing the 256-colour probe response",
		`(?m)[ \t]*if \( \(char_u \*\)getenv\(\(char \*\)\(\(char_u \*\)"COLORS"\)\)  == NULL\)\n` +
			`[ \t]*\{\n([ \t]*may_adjust_color_count\(256\);\n)[ \t]*\}\n`, "${1}"},
}

// NoTerm makes the terminal what the build says it is.
//
// The environment stops choosing: no $TERM, no $LINES/$COLUMNS, no $COLORS, and
// the fallback becomes the only path -- so it has to name the 256-colour table
// rather than plain xterm, or the colours go with the lookup.
func NoTerm(text []byte, w io.Writer) ([]byte, error) {
	// Brace-matched, not regex-matched: this block contains two inner `if`s
	// and a lazy pattern stops at the first of their closing braces.
	text, err := cutil.DropIf(text, `(?m)^[ \t]*if \(columns == 0 \|\| rows == 0 \|\| `+
		`vim_strchr\(p_cpo, CPO_TSIZE\) != NULL\)$`, 1)
	if err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  noterm       $LINES and $COLUMNS overriding the kernel")

	for _, e := range notermEdits {
		var ok bool
		text, ok = replaceFirst(regexp.MustCompile(e.pat), text, e.repl)
		if !ok {
			return nil, fmt.Errorf("noterm: %s -- not found", e.what)
		}
		fmt.Fprintf(w, "  noterm       %s\n", e.what)
	}

	// Only a getenv counts.  "TERM" is also a highlight-group key -- `:hi
	// term=bold` -- and the name of SIGTERM in the signal table, and a bare
	// substring test flags both.
	for _, bad := range []string{"TERM", "LINES", "COLUMNS", "COLORS"} {
		if regexp.MustCompile(`getenv\([^)]*"` + bad + `"`).Match(text) {
			return nil, fmt.Errorf("noterm: something still calls getenv(%q)", bad)
		}
	}
	fmt.Fprintln(w, "  noterm       the terminal is xterm-256color by construction")
	return text, nil
}
