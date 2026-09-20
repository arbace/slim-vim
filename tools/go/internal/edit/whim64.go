package edit

import (
	"bytes"
	"io"
	"regexp"
)

// openLineDecls and internalFormatDecls are the declarations these two
// functions lose, paired with the report line the heredoc printed for each.
//
// THE MESSAGES ARE MALFORMED AND THAT IS DELIBERATE.  The Python derived them
// from the regular expression -- `d.split('\\*')[-1].split(' ')[-1]` and a
// re.sub over the escapes -- and the derivation is sloppy: "open_line declaring
// 0" twice, "open_line declaring NULL" twice, "open_line declaring
// \t]+lead_len", "has_format_option (FO_INS_BLANK );" with the space the escape
// left behind.  They are written out here exactly as the derivation produces
// them, because the report is what this port has to reproduce and tidying it
// would change every phase log in the tree, silently, invisibly to the boundary.
var openLineDecls = []struct{ pattern, what string }{
	{`int[ \t]+extra_len = 0;`, "open_line declaring 0"},
	{`int[ \t]+lead_len;`, `open_line declaring \t]+lead_len`},
	{`int[ \t]+comment_start = 0;`, "open_line declaring 0"},
	{`char_u[ \t]+\*lead_flags;`, "open_line declaring lead_flags"},
	{`char_u[ \t]+\*leader = NULL;`, "open_line declaring NULL"},
	{`char_u[ \t]+\*allocated = NULL;`, "open_line declaring NULL"},
}

var internalFormatDecls = []struct{ pattern, what string }{
	{`int[ \t]+fo_ins_blank = has_format_option\(FO_INS_BLANK\);`, "internal_format: int fo_ins_blank = has_format_option (FO_INS_BLANK );"},
	{`int[ \t]+fo_multibyte = has_format_option\(FO_MBYTE_BREAK\);`, "internal_format: int fo_multibyte = has_format_option (FO_MBYTE_BREAK );"},
	{`int[ \t]+fo_rigor_tw  = has_format_option\(FO_RIGOROUS_TW\);`, "internal_format: int fo_rigor_tw = has_format_option (FO_RIGOROUS_TW );"},
	{`int[ \t]+fo_white_par = has_format_option\(FO_WHITE_PAR\);`, "internal_format: int fo_white_par = has_format_option (FO_WHITE_PAR );"},
	{`colnr_T[ \t]+leader_len;`, "internal_format: colnr_T leader_len;"},
	{`int[ \t]+no_leader = FALSE;`, "internal_format: int no_leader = FALSE;"},
	{`int[ \t]+do_comments = \(flags & INSCHAR_DO_COM\);`, "internal_format: int do_comments = (flags & INSCHAR_DO_COM );"},
	{`int[ \t]+did_do_comment = FALSE;`, "internal_format: int did_do_comment = FALSE;"},
	{`int[ \t]+first_line = TRUE;`, "internal_format: int first_line = TRUE;"},
	{`int[ \t]+skip_pos;`, "internal_format: int skip_pos;"},
	{`skip_pos = 0;`, "internal_format: skip_pos = 0;"},
	{`int[ \t]+wcc;`, "internal_format: int wcc;"},
	{`wcc = 0;`, "internal_format: wcc = 0;"},
}

const oldDispatch = `        case OP_FILTER:
            if (vim_strchr(p_cpo, CPO_FILTER) != NULL)
            {
                AppendToRedobuff((char_u *)"!\r");
            }
            else
            {
                bangredo = TRUE;
            }

        __attribute__((fallthrough));
        case OP_INDENT:
        case OP_COLON:

            if (oap->op_type == OP_INDENT)
            {
                op_reindent(oap, get_indent);
                break;
            }

            op_colon(oap);
            break;
`

const newDispatch = `        case OP_COLON:
            op_colon(oap);
            break;
`

var noLeaderTest = regexp.MustCompile(`(?m)^[ \t]*if \(no_leader\)\n`)

// Whim64 takes 'formatoptions' and everything only it reached: the comment
// leader in open_line, auto-formatting, the gq operator, and the C-indenting
// flag that ten writers set and nothing read.
func Whim64(text []byte, w io.Writer) ([]byte, error) {
	e := New("noformatopts", text, w)

	// open_line: no leader to find, copy or align
	e.InFunction("open_line", func(e *E) {
		e.Cut(`(?m)^[ \t]*if \(flags & OPENLINE_DO_COM\)\n[ \t]*\{\n[ \t]*lead_len = get_leader_len\(ptr, NULL, FALSE, TRUE\);\n[ \t]*\}\n[ \t]*else\n[ \t]*\{\n[ \t]*lead_len = 0;\n[ \t]*\}\n`,
			2, "smartindent looking for a comment leader")
		e.Sub(`\( ?lead_len == 0 && ptr\[0\] == '#'\)`, "(ptr[0] == '#')", 2,
			"smartindent after a # line not asking about a leader")
		// The leader block first: it holds lead_len = 0 statements and an
		// if (lead_len > 0) of its own, which would throw every count after it.
		e.DropIf(`(?m)^[ \t]*if \(lead_len > 0\)\n[ \t]*\{\n[ \t]*char_u[ \t]+\*lead_repl = NULL;$`,
			"copying, replacing and aligning a comment leader")
		e.FoldNever(`(?m)^[ \t]*if \(flags & OPENLINE_DO_COM\)$`, "a new line finding the leader to repeat")
		e.Lines(`lead_len = 0;`, 1, "a new line with no leader")
		e.FoldNever(`(?m)^[ \t]*if \(lead_len > 0\)$`, "smartindent treating a comment line specially")
		e.FoldNever(`(?m)^[ \t]*if \(lead_len\)$`, "the new line starting with its leader")
		e.Lines(`end_comment_pending = NUL;`, 2, "a new line clearing the pending comment end")
		e.Literal("if (trunc_line && !(flags & OPENLINE_KEEPTRAIL))", "if (trunc_line)",
			"a broken line always losing its trailing blanks ('w')")
		e.DropIf(`(?m)^[ \t]*if \( \(\(\(State\) & REPLACE_FLAG\) && !\(\(State\) & VREPLACE_FLAG\)\) \)$\n[ \t]*\{\n[ \t]*while \(lead_len-- > 0\)`,
			"Replace mode pushing a NUL per leader byte")
		e.Literal("if (newindent == 0 && !(flags & OPENLINE_COM_LIST))", "if (newindent == 0)",
			"the second-line indent no longer for a comment list")
		e.Lines(`vim_free\(allocated\);`, 1, "freeing the leader")
		// extra_len sized the leader's allocation and nothing else
		e.Lines(`extra_len = \(int\) strlen\(\(char \*\)\(p_extra\)\) ;`, 1,
			"measuring the text after the cursor for the leader")
		for _, d := range openLineDecls {
			e.Lines(d.pattern, 1, d.what)
		}
	})
	e.Literal("has_format_option(FO_RET_COMS) ? OPENLINE_DO_COM : 0", "0", "Enter in Insert mode repeating a leader ('r')")
	e.Literal("has_format_option(FO_OPEN_COMS) ? OPENLINE_DO_COM : 0", "0", "o and O repeating a leader ('o')")

	// insertchar: 'b' and 'l' off, no comment end to complete
	e.InFunction("insertchar", func(e *E) {
		e.Lines(`int[ \t]+fo_ins_blank;`, 1, "insertchar declaring fo_ins_blank")
		e.Lines(`fo_ins_blank = has_format_option\(FO_INS_BLANK\);`, 1, "insertchar asking for 'b'")
		e.Literal(" && (curwin->w_cursor.lnum != Insstart.lnum || ((!has_format_option(FO_INS_LONG) || Insstart_textlen <= (colnr_T)textwidth) && (!fo_ins_blank || Insstart_blank_vcol <= (colnr_T)textwidth)))",
			"", "wrapping a line that was already long when Insert began ('l', 'b')")
		e.DropIf(`(?m)^[ \t]*if \(did_ai && c == end_comment_pending\)$`, "typing the last character of a comment end")
		e.Lines(`end_comment_pending = NUL;`, 1, "insertchar clearing the pending comment end")
	})
	e.Lines(`static colnr_T[ \t]+Insstart_textlen;`, 1, "the length of the line Insert began on")
	e.Lines(`static colnr_T[ \t]+Insstart_blank_vcol;`, 1, "the column of the first blank typed")
	e.Lines(`Insstart_textlen = \(colnr_T\)linetabsize_str\(ml_get_curline\(\)\);`, 3, "measuring the line Insert began on")
	e.Lines(`Insstart_blank_vcol = MAXCOL;`, 1, "resetting the first blank typed")
	e.DropIfMany(`(?m)^[ \t]*if \(Insstart_blank_vcol == MAXCOL && curwin->w_cursor\.lnum == Insstart\.lnum\)$`, 2,
		"remembering the first blank typed")
	e.Lines(`end_comment_pending = NUL;`, 1, "ins_bs clearing the pending comment end")
	e.Lines(`static int[ \t]+end_comment_pending[ \t]*=[ \t]*NUL[ \t]*;`, 1, "the pending comment end")

	// 'a' and 'w': no auto-formatting
	e.InFunction("stop_insert", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(!ins_need_undo && has_format_option\(FO_AUTO\)\)$`, "leaving Insert mode auto-formatting")
	})
	e.InFunction("stop_insert", func(e *E) {
		e.Lines(`check_auto_format\(TRUE\);`, 1, "leaving Insert mode removing an auto-format space")
	})
	e.InFunction("ins_bs", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(has_format_option\(FO_AUTO\) && has_format_option\(FO_WHITE_PAR\)\)$`,
			"backspacing over a line break dropping a trailing space")
	})
	e.InFunction("do_pending_operator", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(oap->motion_type == MLINE && has_format_option\(FO_AUTO\) && u_save_cursor\(\) == OK\)$`,
			"a linewise delete auto-formatting")
	})
	e.InFunction("op_delete", func(e *E) {
		e.Cut(`(?m)^[ \t]*if \(oap->op_type == OP_DELETE\)\n[ \t]*\{\n[ \t]*auto_format\(FALSE, TRUE\);\n[ \t]*\}\n`, 1,
			"a characterwise delete auto-formatting")
	})
	e.Lines(`auto_format\((?:FALSE|TRUE), (?:FALSE|TRUE)\);`, 15, "the other calls to auto_format")
	for _, name := range []string{"auto_format", "check_auto_format", "paragraph_start"} {
		e.deleteDefinition(name, name+", which only a flag that is off reached")
	}

	// J: 'j', 'M' and 'B' off
	e.InFunction("do_join", func(e *E) {
		e.Cut(`(?m)^[ \t]*int[ \t]+remove_comments = \(use_formatoptions == TRUE\)\n[ \t]*&& has_format_option\(FO_REMOVE_COMS\);\n`, 1,
			"J asking for 'j'")
		e.Lines(`int[ \t]+\*comments = NULL;`, 1, "J declaring the leader offsets")
		e.Lines(`int[ \t]+prev_was_comment;`, 1, "J declaring prev_was_comment")
		e.DropIfMany(`(?m)^[ \t]*if \(remove_comments\)$`, 4, "J removing comment leaders")
		e.Literal(" && (!has_format_option(FO_MBYTE_JOIN) || (utf_ptr2char(curr) < 0x100 && endcurr1 < 0x100)) && (!has_format_option(FO_MBYTE_JOIN2) || (utf_ptr2char(curr) < 0x100 && !(utf_eat_space(endcurr1))) || (endcurr1 < 0x100 && !(utf_eat_space(utf_ptr2char(curr)))))",
			"", "J inserting no space between multibyte characters ('M', 'B')")
	})

	// internal_format: 't' alone, no leader
	e.InFunction("internal_format", func(e *E) {
		for _, d := range internalFormatDecls {
			e.Lines(d.pattern, 1, d.what)
		}
		if !e.Failed() {
			t := e.Text()
			m := noLeaderTest.FindIndex(t)
			end := []byte("        if (leader_len == 0)\n        {\n            no_leader = TRUE;\n        }\n")
			z := bytes.Index(t, end)
			if m == nil || z < 0 || bytes.Count(t, end) != 1 {
				e.Refuse("internal_format -- the leader lookup was not found once")
				return
			}
			out := append([]byte{}, t[:m[0]]...)
			e.Set(append(out, t[z+len(end):]...))
			e.say("wrapping a line looking up its leader ('c')")
		}
		e.Literal("if (!(flags & INSCHAR_FORMAT) && leader_len == 0 && !has_format_option(FO_WRAP))",
			"if (!(flags & INSCHAR_FORMAT) && p_paste)", "wrapping only with 't', which 'paste' turns off")
		e.Literal("while ((!fo_ins_blank && !has_format_option(FO_INS_VI)) || (flags & INSCHAR_FORMAT) || curwin->w_cursor.lnum != Insstart.lnum || curwin->w_cursor.col >= Insstart.col)",
			"for (;;)", "breaking only at blanks typed in this Insert ('v', 'b')")
		e.DropIf(`(?m)^[ \t]*if \(wcc < 2\)$`, "counting the blanks before a break")
		e.DropIf(`(?m)^[ \t]*if \(has_format_option\(FO_PERIOD_ABBR\) && cc == '\.' && wcc < 2\)$`, "not breaking after a period ('p')")
		e.FoldNever(`(?m)^[ \t]*else if \(\(cc >= 0x100 \|\| !utf_allow_break_before\(cc\)\) && fo_multibyte\)$`,
			"breaking between multibyte characters ('m', ']')")
		e.DropIf(`(?m)^[ \t]*if \(has_format_option\(FO_ONE_LETTER\)\)$`, "not breaking after a one-letter word ('1')")
		e.Cut(`(?m)^[ \t]*if \(curwin->w_cursor\.col < leader_len\)\n[ \t]*\{\n[ \t]*break;\n[ \t]*\}\n\n?`, 1, "not breaking inside the leader")
		e.Literal(" && (!fo_white_par || curwin->w_cursor.col < startcol)", "", "keeping a trailing blank ('w')")
		e.FoldAlwaysMany(`(?m)^[ \t]*if \(!fo_white_par\)$`, 2, "removing the blanks at the break ('w')")
		e.Literal("open_line(FORWARD, OPENLINE_DELSPACES + OPENLINE_MARKFIX + (fo_white_par ? OPENLINE_KEEPTRAIL : 0) + (do_comments ? OPENLINE_DO_COM : 0) + OPENLINE_FORMAT + ((flags & INSCHAR_COM_LIST) ? OPENLINE_COM_LIST : 0), ((flags & INSCHAR_COM_LIST) ? second_indent : old_indent), &did_do_comment);",
			"open_line(FORWARD, OPENLINE_DELSPACES + OPENLINE_MARKFIX, old_indent, NULL);", "the break opening a line with no leader")
		e.DropIf(`(?m)^[ \t]*if \(did_do_comment\)$`, "a leader found by the new line")
		// second_indent is -1: ins_char() is the only caller left once the operator goes
		e.DropIf(`(?m)^[ \t]*if \(first_line\)$`, "the first broken line's second-line indent ('2', 'n')")
		e.FoldAlways(`(?m)^[ \t]*if \(!\(flags & INSCHAR_COM_LIST\)\)$`, "a comment list keeping its indent")
	})

	// format_lines() and fmt_check_par() are NOT folded for the options: the
	// operator section below deletes both outright, and folding a function that
	// is about to go is work this phase would throw away.

	// the rest of 'comments'
	e.InFunction("find_decl", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(get_leader_len\(ml_get_curline\(\), NULL, FALSE, TRUE\) > 0\)$`, "gd skipping comment lines")
	})
	e.InFunction("nv_percent", func(e *E) {
		e.FoldNever(`(?m)^[ \t]*if \(vim_strchr\(p_cpo, CPO_MATCH\) == NULL && buf_has_cstyle_comments\(\)\)$`, "% skipping a // comment")
	})

	// 'paragraphs' and 'sections'
	e.InFunction("startPS", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(\*s == '\.' && \(inmacro\(p_sections, s \+ 1\) \|\| \(!para && inmacro\(p_para, s \+ 1\)\)\)\)$`,
			"an nroff macro starting a paragraph or section")
	})

	// the format operator: gq, gw, and gqq/gwgw
	e.InFunction("nv_g_cmd", func(e *E) {
		e.Cut(`(?m)^[ \t]*case 'q':\n[ \t]*case 'w':\n[ \t]*oap->cursor_start = curwin->w_cursor;\n[ \t]*__attribute__\(\(fallthrough\)\);\n`, 1,
			"gq and gw as operators")
	})
	e.InFunction("nv_record", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(cap->oap->op_type == OP_FORMAT\)$`, "gqq and gqgq doubling the operator")
	})
	e.InFunction("do_pending_operator", func(e *E) {
		e.Cut(`(?m)^[ \t]*case OP_FORMAT:\n[ \t]*\{\n[ \t]*op_format\(oap, FALSE\);\n[ \t]*\}\n[ \t]*break;\n[ \t]*case OP_FORMAT2:\n[ \t]*op_format\(oap, TRUE\);\n[ \t]*break;\n`, 1,
			"the operator reaching the formatter")
	})

	// gd and gD
	e.InFunction("nv_g_cmd", func(e *E) {
		e.Cut(`(?m)^[ \t]*case 'd':\n[ \t]*case 'D':\n[ \t]*nv_gd\(oap, cap->nchar, \(int\)cap->count0\);\n[ \t]*break;\n\n?`, 1, "gd and gD")
	})

	// The three go by hand rather than by sweep: comp_textwidth() loses its
	// argument below, and format_lines() would still be calling it with one when
	// the sweep compiles.
	for _, name := range []string{"op_format", "format_lines", "fmt_check_par"} {
		e.deleteDefinition(name, name+", which only gq and gw reached")
	}

	// what only the formatter set: INSCHAR_FORMAT
	e.InFunction("insertchar", func(e *E) {
		e.Lines(`int[ \t]+force_format = flags & INSCHAR_FORMAT;`, 1, "insertchar asking whether this is a whole-line format")
		e.Literal("textwidth = comp_textwidth(force_format);", "textwidth = comp_textwidth();", "the width to wrap at")
		e.Literal("if (textwidth > 0 && (force_format || (! ((c) == ' ' || (c) == '\\t')  && !((State & REPLACE_FLAG) && !(State & VREPLACE_FLAG) && *ml_get_cursor() != NUL))))",
			"if (textwidth > 0 && ! ((c) == ' ' || (c) == '\\t')  && !((State & REPLACE_FLAG) && !(State & VREPLACE_FLAG) && *ml_get_cursor() != NUL))",
			"wrapping only a character that was typed")
		e.Literal("internal_format(textwidth, second_indent, flags, c == NUL, c);",
			"internal_format(textwidth, second_indent, flags, FALSE, c);", "the wrap never being a whole-line format")
		e.DropIf(`(?m)^[ \t]*if \(c == NUL\)$`, "insertchar called with no character to insert")
	})
	e.InFunction("comp_textwidth", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(ff && textwidth == 0\)$`, "the width gq used when 'textwidth' is 0")
		e.Literal("comp_textwidth(int         ff)", "comp_textwidth(void)", "comp_textwidth without its gq flag")
	})
	e.Literal("static int comp_textwidth(int ff);", "static int comp_textwidth(void);", "comp_textwidth's prototype")
	e.Literal("cols = comp_textwidth(FALSE);", "cols = comp_textwidth();", "the change list asking for the width")
	e.InFunction("internal_format", func(e *E) {
		e.Literal("if (!(flags & INSCHAR_FORMAT) && p_paste)", "if (p_paste)", "wrapping stopped only by 'paste'")
	})
	e.InFunction("internal_format", func(e *E) {
		e.Literal("if (!format_only && haveto_redraw)", "if (haveto_redraw)", "the wrap always redrawing")
	})

	// oparg_T's cursor_start was gq's alone, and goes by hand.  deadfields.py
	// keeps every field of a type that is ever initialised WITHOUT designators,
	// because a positional initialiser names no field and removing one silently
	// shifts what the rest fill -- and `oparg_T oa = { 0 };` in pagescroll() is
	// exactly that.  `{ 0 }` fills only the first field, so removing a later one
	// is safe here.
	e.Lines(`pos_T[ \t]+cursor_start;`, 1, "the cursor gw returned to")

	// the = operator, and what only the unreachable ! operator left behind
	e.Sub(`(?m)^([ \t]*\{'=', )nv_operator(, 0, 0\} ,)$`, "${1}nv_error${2}", 1,
		"= in Normal and Visual mode points at nv_error")
	e.InFunction("do_pending_operator", func(e *E) {
		e.Literal(oldDispatch, newDispatch, "the filter and indent operators being dispatched")
	})
	e.InFunction("do_pending_operator", func(e *E) {
		e.Literal(" || oap->op_type == OP_FILTER", "", "a filter deciding whether the motion is inclusive")
	})
	e.InFunction("op_colon", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(oap->op_type != OP_COLON\)$`, "the ! typed after an operator range")
	})
	e.InFunction("do_bang", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(bangredo\)$`, "the ! operator putting its command in the redo buffer")
	})
	// That block held the only `goto theend`, and a label with nothing jumping
	// to it is a warning.  The free below it runs either way, so only the marker
	// goes.
	e.InFunction("do_bang", func(e *E) {
		e.Lines(`theend:`, 1, "do_bang's label, which only the redo block jumped to")
	})

	// what C-indenting left behind.  Three of the ten writes are the whole body
	// of an `if`, so the test goes with them rather than leaving an empty block.
	// Each is scoped to its function: `if (inindent(0))` also guards
	// do_pending_operator's `oap->motion_type = MLINE`, which stays, and an
	// unscoped drop would have had two matches to choose between.
	e.InFunction("edit", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(inindent\(0\)\)$`, "a space typed in the indent forbidding a reindent")
	})
	e.InFunction("ins_bs", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(in_indent\)$`, "a backspace in the indent forbidding a reindent")
	})
	e.InFunction("ins_tab", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(ind\)$`, "a Tab in the indent forbidding a reindent")
	})
	e.Lines(`can_cindent = (?:TRUE|FALSE);`, 7, "the other places that armed or disarmed a reindent")
	e.InFunction("internal_format", func(e *E) {
		e.Lines(`set_can_cindent\(TRUE\);`, 1, "a wrapped line arming a reindent")
	})
	e.deleteDefinition("set_can_cindent", "set_can_cindent, which only wrote a flag nothing read")
	e.Lines(`static int[ \t]+can_cindent;`, 1, "can_cindent itself, written ten times and read none")

	// cindent_on() is `return FALSE`; its two callers fold and the sweep takes it.
	e.InFunction("ins_bs", func(e *E) {
		e.Literal("if (mode == BACKSPACE_LINE && (curbuf->b_p_ai || cindent_on()))",
			"if (mode == BACKSPACE_LINE && curbuf->b_p_ai)", "CTRL-U keeping the indent for 'autoindent' alone")
	})
	e.InFunction("insertchar", func(e *E) {
		e.Literal(" && !cindent_on()", "", "the multi-character insert asking whether C-indenting is on")
	})
	return e.Done()
}

func init() { register("whim64", Whim64) }
