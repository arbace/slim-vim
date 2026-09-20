package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

var nofencsEdits = []struct{ what, pat, repl string }{
	{"the reset that restored a unicode 'fileencodings'",
		`(?m)[ \t]*else if \(\(char_u \*\*\)varp == &p_fencs && enc_utf8\)\n` +
			`[ \t]*\{\n[ \t]*newval = fencs_utf8_default;\n[ \t]*\}\n`, ""},
	{"readfile choosing between an empty list and a list",
		`(?m)[ \t]*else if \(\*p_fencs == NUL\)\n[ \t]*\{\n` +
			`([ \t]*fenc = curbuf->b_p_fenc;\n[ \t]*fenc_alloced = FALSE;\n)` +
			`[ \t]*\}\n[ \t]*else\n[ \t]*\{\n` +
			`[ \t]*fenc_next = p_fencs;\n` +
			`[ \t]*fenc = next_fenc\(&fenc_next, &fenc_alloced\);\n[ \t]*\}\n`,
		"    else\n    {\n${1}    }\n"},
}

// tencCond is the head of the block did_set_encoding used to convert between
// 'termencoding' and 'encoding'.
const tencCond = `(?m)^[ \t]*if \(\(\(varp == &p_enc && \*p_tenc != NUL\) \|\| varp == &p_tenc\)\)$`

// dropTencBlock needs BRACE MATCHING and not a regex, for the reason this tree
// has now recorded three times: a lazy `(?:[^\n]*\n)*?\}` stops at the first
// line that is only a brace, which here is the inner `if (convert_setup(...))`'s
// -- leaving the outer `}` and the function's own `}` with nothing to close,
// and gcc reporting it as "expected identifier or '(' before 'return'".
func dropTencBlock(text []byte) ([]byte, error) {
	blanked := cutil.Blank(text)
	m := regexp.MustCompile(tencCond).FindIndex(text)
	if m == nil {
		return nil, fmt.Errorf("nofencs: did_set_encoding no longer converts between " +
			"'termencoding' and 'encoding'")
	}
	lp := m[0] + bytes.IndexByte(text[m[0]:], '(')
	rp := cutil.Match(blanked, lp)
	i := rp + 1
	for i < len(text) && (text[i] == ' ' || text[i] == '\t' || text[i] == '\n') {
		i++
	}
	if i >= len(text) || text[i] != '{' {
		return nil, fmt.Errorf("nofencs: that condition does not open a block")
	}
	closing := cutil.Match(blanked, i)
	end := closing + 1
	for end < len(text) && (text[end] == ' ' || text[end] == '\t') {
		end++
	}
	if end < len(text) && text[end] == '\n' {
		end++
	}
	if end < len(text) && text[end] == '\n' {
		end++
	}
	out := make([]byte, 0, len(text))
	out = append(out, text[:m[0]]...)
	return append(out, text[end:]...), nil
}

// NoFencs leaves p_fencs and p_tenc as a declaration and a row, so the rows
// can go next.
func NoFencs(text []byte, w io.Writer) ([]byte, error) {
	for _, e := range nofencsEdits {
		re := regexp.MustCompile(e.pat)
		n := len(re.FindAll(text, -1))
		if n != 1 {
			return nil, fmt.Errorf("nofencs: %s -- expected 1, matched %d", e.what, n)
		}
		text = re.ReplaceAll(text, []byte(e.repl))
		fmt.Fprintf(w, "  nofencs      %s\n", e.what)
	}

	text, err := dropTencBlock(text)
	if err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nofencs      converting between 'termencoding' and 'encoding'")

	for _, v := range []string{"p_fencs", "p_tenc"} {
		// The declaration and the options[] row are not reads.
		n := len(regexp.MustCompile(`\b`+v+`\b`).FindAll(text, -1))
		if n > 2 {
			return nil, fmt.Errorf("nofencs: %s still has %d mentions; the row cannot go "+
				"while anything reads it", v, n)
		}
	}

	fmt.Fprintln(w, "  nofencs      p_fencs and p_tenc are now declaration and row only")
	return text, nil
}
