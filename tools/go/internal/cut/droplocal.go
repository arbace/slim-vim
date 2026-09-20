package cut

import (
	"bytes"
	"fmt"
	"regexp"
)

// DropLocal removes a buffer-local option field and its PLUMBING -- the
// declaration, the assignments, the free, and the get_varp case that hands its
// address out -- and refuses when anything else still names it.
//
// The refusal is the point.  Plumbing is what the phase may remove on its own;
// a mention that is left over is a READER, and a reader has to be dealt with
// by the phase before the field can go.  It also refuses when it found fewer
// than three sites, because the field, an initialiser and a get_varp case are
// the minimum shape -- fewer means the shape has moved and a silent partial
// cut would leave the struct and its users disagreeing.
func DropLocal(text []byte, bvar string) (out []byte, n int, err error) {
	if !bytes.Contains(text, []byte(bvar)) {
		return nil, 0, fmt.Errorf("droplocal: there is no %s here", bvar)
	}
	q := regexp.QuoteMeta(bvar)
	pats := []string{
		`(?m)^[ \t]*(?:char_u[ \t]*\*|int[ \t]+|long[ \t]+)` + q + `;\n`,
		`(?m)^[ \t]*buf->` + q + ` = [^\n]*;\n`,
		`(?m)^[ \t]*curbuf->` + q + ` = -1;\n`,
		`(?m)^[ \t]*(?:check|clear)_string_option\(&buf->` + q + `\);\n`,
		`(?m)^[ \t]*case[^\n]*\n[ \t]*return \(char_u \*\)&\(curbuf->` + q + `\);\n`,
		`(?m)^[ \t]*case[^\n]*\n[ \t]*return [^\n]*curbuf->` + q + `[^\n]*\n` +
			`[ \t]*\? \(char_u \*\)&\(curbuf->` + q + `\) : p->var;\n`,
	}
	for _, p := range pats {
		re := regexp.MustCompile(p)
		n += len(re.FindAll(text, -1))
		text = re.ReplaceAll(text, nil)
	}
	if n < 3 {
		return nil, 0, fmt.Errorf("droplocal: %s: only %d plumbing sites, expected at "+
			"least the field, an initialiser and a get_varp case -- the shape has moved",
			bvar, n)
	}
	left := len(regexp.MustCompile(`\b`+q+`\b`).FindAll(text, -1))
	if left > 0 {
		return nil, 0, fmt.Errorf("droplocal: %s still has %d mentions after the plumbing "+
			"went -- those are readers, and the phase has to deal with them before the "+
			"field can go", bvar, left)
	}
	return text, n, nil
}
