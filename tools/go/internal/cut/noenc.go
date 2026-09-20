package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// The dispatch in mb_init(): everything from the first `else if` that sniffs a
// prefix down to the enc_latin1like line, replaced by the one case left.
const oldDispatchStart = `    else if ( strncmp((char *)(p_enc), (char *)("8bit-"), (5))  == 0`

const newDispatch = `    if ( strcmp((char *)(p_enc), (char *)("utf-8"))  != 0)
    {
        return e_invalid_argument;
    }

    enc_unicode = 0;
    enc_utf8 = TRUE;
    enc_dbcs = 0;
    has_mbyte = TRUE;
    enc_latin1like = TRUE;
`

// dropFencs: mb_init() installs a default 'fileencodings' whenever the
// encoding is unicode and the user has not set one.  With enc_utf8 now always
// true that fires at every startup, and it reaches the option BY NAME --
// set_string_option_direct("fencs", ...) -- so dropping the row turns it into
// E685 and then a segfault before the first keystroke.
const dropFencs = "    if (enc_utf8 && !option_was_set((char_u *)\"fencs\"))\n" +
	"    {\n        set_fencs_unicode();\n    }\n\n"

// And a second caller, which the first sweep does not remove because it is not
// dead: set_option_default() special-cases 'fileencodings' so that RESETTING
// it picks the unicode list rather than the compiled default.
const dropFencsDefaultOld = "            if (options[opt_idx].var == (char_u *)&p_fencs && enc_utf8)\n" +
	"            {\n                set_fencs_unicode();\n            }\n" +
	"            else if (options[opt_idx].indir != PV_NONE)\n"

const dropFencsDefaultNew = "            if (options[opt_idx].indir != PV_NONE)\n"

var noencStubs = []struct{ name, stub string }{
	{"my_iconv_open", "    return (void *)(iconv_t)-1;"},
	{"convert_setup", "    vcp->vc_type = CONV_NONE;\n" +
		"    vcp->vc_factor = 1;\n" +
		"    vcp->vc_fail = FALSE;\n" +
		"    return OK;"},
	{"string_convert", "    return NULL;"},
	{"check_for_bom", "    *lenp = 0;\n    return NULL;"},
	{"make_bom", "    return 0;"},
	{"convert_input_safe", "    if (restp != NULL)\n    {\n        *restp = NULL;\n" +
		"    }\n    return len;"},
}

// noencIconvBlocks are the last two symbols, and the only place this phase
// touches readfile() or buf_write().  my_iconv_open() now always fails, so
// every one of these blocks is a branch that can no longer be taken -- but the
// calls inside them are what keep `iconv` and `iconv_close` in the symbol
// table, and a dependency that is linked in and never reached is exactly what
// this pipeline exists to remove.
//
// EVERY ANCHOR NAMES A LINE OF THE BODY, not just the condition.
// `if (fio_flags == 0)` occurs twice in readfile() and the first one has an
// `else` after it; deleting that block left an orphaned `else`, which gcc
// reported as "expected '}' before 'else'" and then as two undefined labels
// six hundred lines away.
var noencIconvBlocks = []struct{ pat, what string }{
	{`(?m)^[ \t]*if \(ip->bw_iconv_fd != \(iconv_t\)-1\)\n[ \t]*\{\n[ \t]*const char`,
		"buf_write's conversion"},
	{`(?m)^[ \t]*if \(converted && wb_flags == 0\)\n[ \t]*\{\n` +
		`[ \t]*write_info\.bw_iconv_fd = \(iconv_t\)my_iconv_open`, "buf_write's iconv open"},
	{`(?m)^[ \t]*if \(write_info\.bw_iconv_fd != \(iconv_t\)-1\)\n[ \t]*\{\n` +
		`[ \t]*iconv_close`, "buf_write's iconv close"},
	{`(?m)^[ \t]*if \(fio_flags == 0\)\n[ \t]*\{\n` +
		`[ \t]*iconv_fd = \(iconv_t\)my_iconv_open`, "readfile's iconv open"},
	{`(?m)^[ \t]*if \(iconv_fd != \(iconv_t\)-1\)\n[ \t]*\{\n[ \t]*iconv_close`,
		"readfile's iconv close"},
	{`(?m)^[ \t]*if \(iconv_fd != \(iconv_t\)-1\)\n[ \t]*\{\n[ \t]*const char`,
		"readfile's conversion loop"},
	// Two more closes, nested deeper: one where the read loop gives up on a
	// conversion, one in readfile's exit path.  Indentation differs, the body
	// does not.
	{`(?m)^[ \t]*if \(iconv_fd != \(iconv_t\)-1\)\n[ \t]*\{\n` +
		`[ \t]*iconv_close\(iconv_fd\);\n[ \t]*iconv_fd = \(iconv_t\)-1;\n[ \t]*\}`,
		"the read loop giving up on a conversion"},
	{`(?m)^[ \t]*if \(iconv_fd != \(iconv_t\)-1\)\n[ \t]*\{\n` +
		`[ \t]*iconv_close\(iconv_fd\);\n[ \t]*\}`, "readfile's exit path"},
}

var fencsRow = regexp.MustCompile(
	`(\{"fileencodings","fencs",[^\n]*\n[^\n]*\n[ \t]*\{\(char_u \*\))"[^"]*"`)

// noencDropIfBlock deletes an `if (...)` and the block it guards, by matching
// braces.
func noencDropIfBlock(text []byte, pat, what string) ([]byte, error) {
	blanked := cutil.Blank(text)
	m := regexp.MustCompile(pat).FindIndex(text)
	if m == nil {
		return nil, fmt.Errorf("noenc: %s is not where this expects", what)
	}
	lp := m[0] + bytes.IndexByte(text[m[0]:], '(')
	rp := cutil.Match(blanked, lp)
	i := rp + 1
	for i < len(text) && (text[i] == ' ' || text[i] == '\t' || text[i] == '\n') {
		i++
	}
	if i >= len(text) || text[i] != '{' {
		return nil, fmt.Errorf("noenc: %s does not open a block", what)
	}
	closing := cutil.Match(blanked, i)
	// An `else` after the block means deleting the block alone changes which
	// branch runs, and leaves the `else` with no `if`.
	tail := text[closing+1:]
	if len(tail) > 39 {
		tail = tail[:39]
	}
	if regexp.MustCompile(`^[ \t]*\n[ \t]*else\b`).Match(tail) {
		return nil, fmt.Errorf("noenc: %s has an else branch; deleting the if alone "+
			"would orphan it", what)
	}
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

func noencReplaceBody(text []byte, name, body string) ([]byte, int, error) {
	o, c, found, balanced := cutil.Body(text, name)
	if !found {
		return nil, 0, fmt.Errorf("noenc: %s is not defined at file scope any more", name)
	}
	if !balanced {
		return nil, 0, fmt.Errorf("noenc: %s is unbalanced", name)
	}
	was := bytes.Count(text[o:c], []byte{'\n'})
	out := make([]byte, 0, len(text))
	out = append(out, text[:o]...)
	out = append(out, "{\n"...)
	out = append(out, body...)
	out = append(out, "\n}"...)
	return append(out, text[c+1:]...), was, nil
}

// NoEnc leaves one encoding: nothing calls iconv any more.
func NoEnc(text []byte, w io.Writer) ([]byte, error) {
	i := bytes.Index(text, []byte(oldDispatchStart))
	if i < 0 {
		return nil, fmt.Errorf("noenc: mb_init's encoding dispatch is not where this expects")
	}
	const endMarker = "\n    enc_latin1like = "
	rel := bytes.Index(text[i:], []byte(endMarker))
	if rel < 0 {
		return nil, fmt.Errorf("noenc: mb_init's encoding dispatch is not where this expects")
	}
	j := i + rel + len(endMarker)
	j = j + bytes.IndexByte(text[j:], '\n') + 1
	var buf []byte
	buf = append(buf, text[:i]...)
	buf = append(buf, newDispatch...)
	text = append(buf, text[j:]...)
	fmt.Fprintln(w, "  noenc        mb_init accepts utf-8 and rejects every other value")

	// The function-pointer table: keep the utf-8 arm, drop the other two.
	blanked := cutil.Blank(text)
	k := bytes.Index(text, []byte("    if (enc_utf8)\n    {\n        mb_ptr2len = utfc_ptr2len;"))
	if k < 0 {
		return nil, fmt.Errorf("noenc: the utf-8 arm is not where this expects")
	}
	o1 := k + bytes.IndexByte(blanked[k:], '{')
	c1 := cutil.Match(blanked, o1)
	if c1 < 0 {
		return nil, fmt.Errorf("noenc: the utf-8 arm is unbalanced")
	}
	m := regexp.MustCompile(`^\n    else if \(enc_dbcs != 0\)\n`).FindIndex(text[c1+1:])
	if m == nil {
		return nil, fmt.Errorf("noenc: the dbcs arm does not follow the utf-8 arm")
	}
	at := c1 + 1 + m[1]
	o2 := at + bytes.IndexByte(blanked[at:], '{')
	c2 := cutil.Match(blanked, o2)
	if c2 < 0 {
		return nil, fmt.Errorf("noenc: the dbcs arm is unbalanced")
	}
	m2 := regexp.MustCompile(`^\n    else\n`).FindIndex(text[c2+1:])
	if m2 == nil {
		return nil, fmt.Errorf("noenc: the latin1 arm does not follow the dbcs arm")
	}
	at2 := c2 + 1 + m2[1]
	o3 := at2 + bytes.IndexByte(blanked[at2:], '{')
	c3 := cutil.Match(blanked, o3)
	if c3 < 0 {
		return nil, fmt.Errorf("noenc: the latin1 arm is unbalanced")
	}
	body := cutil.Dedent4(text[o1+bytes.IndexByte(text[o1:], '\n')+1 : bytes.LastIndexByte(text[:c1], '\n')+1])
	buf = nil
	buf = append(buf, text[:k]...)
	buf = append(buf, body...)
	text = append(buf, bytes.TrimLeft(text[c3+1:], "\n")...)
	fmt.Fprintln(w, "  noenc        the latin1 and DBCS character paths lose their only caller")

	if !bytes.Contains(text, []byte(dropFencs)) {
		return nil, fmt.Errorf("noenc: mb_init no longer installs a default 'fileencodings', " +
			"so either this has run already or that code has moved")
	}
	text = bytes.Replace(text, []byte(dropFencs), nil, 1)
	fmt.Fprintln(w, "  noenc        mb_init stops installing a default 'fileencodings'")

	// The row stays -- readfile() dereferences p_fencs, so removing the row
	// would leave a NULL global -- and its content goes instead.  The compiled
	// default is "ucs-bom"; the longer unicode list was the one mb_init()
	// installed at run time, and that has just gone.
	before := text
	text = fencsRow.ReplaceAll(text, []byte(`${1}""`))
	if bytes.Equal(text, before) {
		return nil, fmt.Errorf("noenc: 'fileencodings' does not default to the unicode list, " +
			"so this has run already or the row has moved")
	}
	fmt.Fprintln(w, "  noenc        'fileencodings' defaults to empty; nothing to try")

	if !bytes.Contains(text, []byte(dropFencsDefaultOld)) {
		return nil, fmt.Errorf("noenc: set_option_default no longer special-cases " +
			"'fileencodings', so this has run already or that code moved")
	}
	text = bytes.Replace(text, []byte(dropFencsDefaultOld), []byte(dropFencsDefaultNew), 1)
	fmt.Fprintln(w, "  noenc        resetting 'fileencodings' stops picking a unicode list")

	total := 0
	for _, s := range noencStubs {
		var was int
		var err error
		text, was, err = noencReplaceBody(text, s.name, s.stub)
		if err != nil {
			return nil, err
		}
		total += was
		fmt.Fprintf(w, "  noenc        %-20s was %3d lines, is now a constant answer\n",
			s.name, was)
	}

	for _, b := range noencIconvBlocks {
		var err error
		if text, err = noencDropIfBlock(text, b.pat, b.what); err != nil {
			return nil, err
		}
		fmt.Fprintf(w, "  noenc        %s, a branch that can no longer be taken\n", b.what)
	}

	fmt.Fprintf(w, "  noenc        %d lines stubbed; nothing calls iconv any more\n", total)
	return text, nil
}
