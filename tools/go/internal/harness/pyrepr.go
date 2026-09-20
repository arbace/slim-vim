package harness

import (
	"fmt"
	"strings"
)

// pyRepr is Python's repr() for a str, which Go's %q is NOT.
//
// The difference is the quote character -- repr prefers single quotes, %q
// always uses double -- and it matters here for one reason only: these tools'
// diagnostics ARE what the comparison against the Python reads.  Measured on
// starcheck against a binary that cannot open a file, where both
// implementations correctly detected the same wrong buffer and reported it as
//
//   - gave 'foo bar foobar baz foo ', expected 'foo bar foobar baz '
//   - gave "foo bar foobar baz foo ", expected "foo bar foobar baz "
//
// A port whose only difference from the original is the shape of a quote is
// still a port that a diff refuses, and pretending otherwise by loosening the
// comparison would give up the one piece of evidence these probes have.
//
// The rule: single quotes, unless the value contains a single quote and no
// double quote, in which case double -- and then backslash, the chosen quote,
// and the non-printables escaped as Python escapes them.
//
// THIS REPLACES A ONE-LINE VERSION that lived in termcheck.go and returned
// "'" + s + "'".  That was correct for what it was given -- terminal names,
// none of which needs escaping -- and it is the kind of correct that stops
// being true when a second caller arrives with different data.  The recorded
// baselines carry the single-quoted spelling, and the two agree on every
// string termcheck has ever passed.
func pyRepr(s string) string {
	quote := byte('\'')
	if strings.ContainsRune(s, '\'') && !strings.ContainsRune(s, '"') {
		quote = '"'
	}
	var b strings.Builder
	b.WriteByte(quote)
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '\\':
			b.WriteString(`\\`)
		case c == quote:
			b.WriteByte('\\')
			b.WriteByte(c)
		case c == '\n':
			b.WriteString(`\n`)
		case c == '\r':
			b.WriteString(`\r`)
		case c == '\t':
			b.WriteString(`\t`)
		case c < 0x20 || c == 0x7f:
			b.WriteString(fmt.Sprintf(`\x%02x`, c))
		default:
			b.WriteByte(c)
		}
	}
	b.WriteByte(quote)
	return b.String()
}
