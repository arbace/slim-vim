package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

const (
	eqCArm = `                        if (cindent_on())
                        {
                            indent =
                                 get_c_indent();
                        }
                        else
                        {
                            indent = get_indent();
                        }
`
	eqCNew      = "                        indent = get_indent();\n"
	preprocsOld = "        (curbuf->b_p_si && !curbuf->b_p_cin) ||\n" +
		"        (curbuf->b_p_cin && in_cinkeys('#', ' ', TRUE) && curbuf->b_ind_hash_comment == 0)\n" +
		"        ;"
	preprocsNew  = "        curbuf->b_p_si;"
	fixIndentOld = `    if (curbuf->b_p_lisp && curbuf->b_p_ai)
    {
        if (use_indentexpr_for_lisp())
        {
            do_c_expr_indent();
        }
        else
        {
            fixthisline(get_lisp_indent);
        }
    }
    else if (cindent_on())
    {
        do_c_expr_indent();
    }`
	fixIndentNew = `    if (curbuf->b_p_lisp && curbuf->b_p_ai)
    {
        fixthisline(get_lisp_indent);
    }`
	mayDoSiOld = "    return curbuf->b_p_si\n        && !curbuf->b_p_cin\n        && !p_paste;"
	mayDoSiNew = "    return curbuf->b_p_si\n        && !p_paste;"
)

var cindentLeft = regexp.MustCompile(`\b(?:get_c_indent|in_cinkeys)\b`)

// NoCindent removes 'cindent': the editor cannot read C any more, and says so
// by indenting the way 'autoindent' does.
func NoCindent(text []byte, w io.Writer) ([]byte, error) {
	var err error
	for _, p := range []string{
		`(?m)^[ \t]*if \(cindent_on\(\) && ctrl_x_mode_none\(\)\)$`,
		`(?m)^[ \t]*if \(can_cindent && cindent_on\(\) && ctrl_x_mode_normal\(\)\)$`,
	} {
		if text, err = cutil.DropIf(text, p, 1); err != nil {
			return nil, err
		}
	}
	fmt.Fprintln(w, "  nocindent    insert mode stops re-indenting, and the goto between "+
		"its two tests goes with them")

	var hit bool
	if text, hit = replaceFirst(regexp.MustCompile(
		`(?m)[ \t]*do_cindent = !p_paste && \(curbuf->b_p_cin\)\n`+
			`[ \t]*&& in_cinkeys\([^\n]*\n[ \t]*&& !\(flags & OPENLINE_FORCE_INDENT\);\n`),
		text, ""); !hit {
		return nil, fmt.Errorf("nocindent: open_line's do_cindent is not where this expects")
	}
	if text, err = cutCounted(text, `(?m)^[ \t]*int         do_cindent;\n`,
		"nocindent", "do_cindent's declaration", 1); err != nil {
		return nil, err
	}
	text = bytes.Replace(text,
		[]byte("if (lead_len == 0 && curbuf->b_p_cin && do_cindent && dir == FORWARD"),
		[]byte("if (lead_len == 0 && dir == FORWARD"), 1)
	if text, err = cutil.DropIf(text,
		`(?m)^[ \t]*else if \(do_cindent \|\| \(curbuf->b_p_ai && use_indentexpr_for_lisp\(\)\)\)$`,
		1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nocindent    open_line stops asking whether to indent as C")

	if !bytes.Contains(text, []byte(eqCArm)) {
		return nil, fmt.Errorf("nocindent: the `=` operator's C arm is not where this expects")
	}
	text = bytes.Replace(text, []byte(eqCArm), []byte(eqCNew), 1)
	fmt.Fprintln(w, "  nocindent    `=` indents by the line above, which is what "+
		"'autoindent' does")

	if !bytes.Contains(text, []byte(preprocsOld)) {
		return nil, fmt.Errorf("nocindent: preprocs_left is not where this expects")
	}
	text = bytes.Replace(text, []byte(preprocsOld), []byte(preprocsNew), 1)

	if !bytes.Contains(text, []byte(fixIndentOld)) {
		return nil, fmt.Errorf("nocindent: fix_indent is not where this expects")
	}
	text = bytes.Replace(text, []byte(fixIndentOld), []byte(fixIndentNew), 1)

	// want_cindent is (get_can_cindent() && cindent_on()), so it is FALSE.
	for _, c := range []struct{ pat, what string }{
		{`(?m)^[ \t]*want_cindent = \(get_can_cindent\(\) && cindent_on\(\)\);\n\n?`,
			"ins_compl_stop's want_cindent"},
		{`(?m)[ \t]*if \(want_cindent\)\n[ \t]*\{\n` +
			`[ \t]*do_c_expr_indent\(\);\n[ \t]*want_cindent = FALSE;\n[ \t]*\}\n`,
			"its first use"},
		{`(?m)[ \t]*if \(want_cindent && in_cinkeys\(KEY_COMPLETE, ' ', inindent\(0\)\)\)\n` +
			`[ \t]*\{\n[ \t]*do_c_expr_indent\(\);\n[ \t]*\}\n`, "its second use"},
		{`(?m)^[ \t]*int[ \t]+want_cindent;\n`, "its declaration"},
	} {
		if text, err = cutCounted(text, c.pat, "nocindent", c.what, 1); err != nil {
			return nil, err
		}
	}

	// op_reindent() takes the indenter as a FUNCTION POINTER, which is why a
	// grep for `get_c_indent(` does not find this one.  Without a C indenter,
	// `=` sets each line's indent to the indent it already has: a no-op, which
	// is the honest answer for a buffer whose language the editor cannot read.
	text = bytes.Replace(text, []byte("                op_reindent(oap, get_c_indent);"),
		[]byte("                op_reindent(oap, get_indent);"), 1)

	if text, err = cutil.DropIf(text,
		`(?m)^[ \t]*if \(leader_len == 0 && curbuf->b_p_cin\)$`, 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nocindent    preprocs_left, fix_indent, completion, `=` and the "+
		"comment hunt in internal_format")

	if !bytes.Contains(text, []byte(mayDoSiOld)) {
		return nil, fmt.Errorf("nocindent: may_do_si is not where this expects")
	}
	text = bytes.Replace(text, []byte(mayDoSiOld), []byte(mayDoSiNew), 1)
	fmt.Fprintln(w, "  nocindent    'smartindent' stops deferring to an option that is gone")

	if text, hit = replaceFirst(regexp.MustCompile(
		`(?m)[ \t]*else if \(last_char != ';' && last_char != '\}' && cin_is_cinword\(ptr\)\)\n`+
			`[ \t]*\{\n[ \t]*did_si = TRUE;\n[ \t]*\}\n`), text, ""); !hit {
		return nil, fmt.Errorf("nocindent: 'smartindent' does not consult cin_is_cinword here")
	}

	// FOUR callers, not two: 'shiftwidth' re-parses 'cinoptions' because some
	// of them are expressed in shiftwidths, and check_buf_options() re-parses
	// on every option check.  Neither is about indenting; both just keep the
	// b_ind_* fields in step with a string that no longer exists.
	if text, err = cutCounted(text, `(?m)^[ \t]*parse_cino\(curbuf\);\n`,
		"nocindent", "a parse_cino call", 3); err != nil {
		return nil, err
	}
	if text, err = cutCounted(text, `(?m)^[ \t]*parse_cino\(buf\);\n`,
		"nocindent", "check_buf_options' parse_cino", 1); err != nil {
		return nil, err
	}
	var ok bool
	if text, ok = cutil.DeleteDefinition(text, "parse_cino"); !ok {
		return nil, fmt.Errorf("nocindent: parse_cino is not defined at file scope")
	}
	fmt.Fprintln(w, "  nocindent    'cinwords' for 'smartindent', and 'cinoptions' parsing")

	if text, ok = cutil.DeleteDefinition(text, "do_c_expr_indent"); !ok {
		return nil, fmt.Errorf("nocindent: do_c_expr_indent is not defined at file scope")
	}

	// cindent_on() stays and answers no: five of its seven callers only ask in
	// order to do something else instead.
	blanked := cutil.Blank(text)
	m := regexp.MustCompile(`(?m)^cindent_on\(void\)\n`).FindIndex(text)
	if m == nil {
		return nil, fmt.Errorf("nocindent: cindent_on is not defined at file scope")
	}
	o := m[1] + bytes.IndexByte(blanked[m[1]:], '{')
	c := cutil.Match(blanked, o)
	if c < 0 {
		return nil, fmt.Errorf("nocindent: cindent_on is unbalanced")
	}
	var buf []byte
	buf = append(buf, text[:o]...)
	buf = append(buf, "{\n    return FALSE;\n}"...)
	text = append(buf, text[c+1:]...)
	fmt.Fprintln(w, "  nocindent    cindent_on() answers no, which is now true")

	fmt.Fprintf(w, "  nocindent    %d get_c_indent/in_cinkeys mentions left for the sweep\n",
		len(cindentLeft.FindAll(text, -1)))
	return text, nil
}
