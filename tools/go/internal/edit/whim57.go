package edit

import "io"

// Whim57 takes lisp mode: the indenting, the ';' comment leader, and the ten
// places `%` knew about a lisp comment.
func Whim57(text []byte, w io.Writer) ([]byte, error) {
	e := New("nolisp", text, w)

	e.InFunction("open_line", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(leader == NULL && !use_indentexpr_for_lisp\(\) && curbuf->b_p_lisp && curbuf->b_p_ai\)$`,
			"a new line taking its indent from get_lisp_indent()")
		e.Cut(`(?m)^[ \t]*if \(!p_paste\)\n[ \t]*\{\n[ \t]*\}\n\n?`, 1,
			"open_line's now-empty 'paste' test")
	})
	e.InFunction("buf_init_chartab", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(buf->b_p_lisp\)$`, "'-' as a keyword character")
	})
	e.InFunction("check_linecomment", func(e *E) {
		e.FoldNever(`(?m)^[ \t]*if \(curbuf->b_p_lisp\)$`, "a ';' starting a line comment")
	})
	e.InFunction("op_reindent", func(e *E) {
		e.Always(`(?m)^[ \t]*if \(i != oap->line_count - 1 \|\| oap->line_count == 1 \|\| how != get_lisp_indent\)$`,
			"= skipping the last line only for lisp")
	})
	e.InFunction("fix_indent", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(curbuf->b_p_lisp && curbuf->b_p_ai\)$`, "fix_indent re-indenting lisp")
	})
	e.InFunction("do_pending_operator", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(curbuf->b_p_lisp\)$`, "= indenting lisp")
	})
	e.InFunction("format_lines", func(e *E) {
		e.FoldNever(`(?m)^[ \t]*else if \(curbuf->b_p_lisp\)$`, "gq indenting lisp")
	})

	// findmatchlimit carried a lisp comment state through the whole scan, so
	// this is ten acts rather than one: two locals, six conditions that named
	// them and two that named b_p_lisp directly.
	e.InFunction("findmatchlimit", func(e *E) {
		e.Cut(`(?m)^[ \t]*int[ \t]+lispcomm = FALSE;\n`, 1, "% without a lisp comment state")
		e.Cut(`(?m)^[ \t]*int[ \t]+lisp = curbuf->b_p_lisp;\n`, 1, "% without lisp mode")
		e.Literal("if ((backwards && comment_dir) || lisp || skip_comments)",
			"if ((backwards && comment_dir) || skip_comments)",
			"% looking for a comment only for a comment direction or FM_SKIPCOMM")
		e.DropIf(`(?m)^[ \t]*if \(lisp && comment_col != MAXCOL && pos\.col > \(colnr_T\)comment_col\)$`,
			"% starting inside a lisp comment")
		e.DropIf(`(?m)^[ \t]*if \(lispcomm && pos\.col < \(colnr_T\)comment_col\)$`,
			"% stopping at a lisp comment backwards")
		e.Literal("if (comment_dir || lisp || skip_comments)", "if (comment_dir || skip_comments)",
			"% rescanning a line for lisp")
		e.FoldNever(`(?m)^[ \t]*if \(lisp && comment_col != MAXCOL\)$`,
			"% jumping to a lisp comment backwards")
		e.Literal("if (linep[pos.col] == NUL || (lisp && comment_col != MAXCOL && pos.col == (colnr_T)comment_col))",
			"if (linep[pos.col] == NUL)", "% ending a line at a lisp comment")
		e.Literal("if (pos.lnum == curbuf->b_ml.ml_line_count || lispcomm)",
			"if (pos.lnum == curbuf->b_ml.ml_line_count)", "% stopping at a lisp comment forwards")
		e.Literal("if (lisp || skip_comments)", "if (skip_comments)", "% scanning the next line for lisp")
		e.DropIf(`(?m)^[ \t]*if \(curbuf->b_p_lisp && vim_strchr\(\(char_u \*\)"\{\}\(\)\[\]", c\) != NULL`,
			`% skipping #\( character literals`)
	})
	return e.Done()
}

func init() { register("whim57", Whim57) }
