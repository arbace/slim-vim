package cut

import (
	"fmt"
	"regexp"
)

// rowPattern points a cmdnames[] row's handler at ex_ni.
//
// ANY whitespace before the handler.  Macro expansion left some rows spelled
// `- 1,  ex_nogui ,`, and a pattern written against one space refused :gui and
// :gvim -- loudly, as it should, but the rule is the row, not the spacing.
const rowPattern = `(\[CMD_\w+\] = \{\(char_u \*\)"%s", sizeof\("%s"\) - 1,\s*)(\w+)`

// Retire points each named command's handler at ex_ni, so it answers "not
// implemented" instead of doing something.
//
// It refuses on a name whose row is not there, because a phase that retires
// nothing still reports success otherwise.  A row already pointing at ex_ni is
// counted apart rather than refused: it is already what the phase wants.
func Retire(text []byte, names []string) (out []byte, done, already []string, err error) {
	for _, name := range names {
		q := regexp.QuoteMeta(name)
		pat := regexp.MustCompile(fmt.Sprintf(rowPattern, q, q))
		m := pat.FindSubmatch(text)
		if m == nil {
			return nil, nil, nil, fmt.Errorf(
				"retire: no row for :%s -- the table has moved, and a phase that "+
					"retires nothing still reports success", name)
		}
		if string(m[2]) == "ex_ni" {
			already = append(already, name)
			continue
		}
		locs := pat.FindAllSubmatchIndex(text, -1)
		if len(locs) != 1 {
			return nil, nil, nil, fmt.Errorf("retire: %d rows for :%s, expected one",
				len(locs), name)
		}
		l := locs[0]
		var buf []byte
		buf = append(buf, text[:l[2]]...)
		buf = append(buf, text[l[2]:l[3]]...)
		buf = append(buf, "ex_ni"...)
		buf = append(buf, text[l[1]:]...)
		text = buf
		done = append(done, name)
	}
	return text, done, already, nil
}
