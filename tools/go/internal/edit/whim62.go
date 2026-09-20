package edit

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
)

var expiredWait = regexp.MustCompile(`(?m)^([ \t]*)if \(wait_time <= 0 && did_call_wait_func\)\n`)

// Whim62 takes five buffer options: 'autowrite' and 'autowriteall', 'buftype',
// 'jumpoptions', 'updatetime' and 'buflisted', and 'filetype' with them.
func Whim62(text []byte, w io.Writer) ([]byte, error) {
	e := New("nobufopts", text, w)

	// 'autowrite' and 'autowriteall' -- first, since autowrite() reads bt_dontwrite()
	e.InFunction("getfile", func(e *E) {
		e.Literal(" && autowrite(curbuf, forceit) == FAIL)", ")", "switching files trying autowrite first")
	})
	e.InFunction("check_changed", func(e *E) {
		e.Literal(" && (!(flags & CCGD_AW) || autowrite(buf, forceit) == FAIL))", ")", "a changed buffer trying autowrite first")
	})
	e.InFunction("nv_gotofile", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(curbufIsChanged\(\) && curbuf->b_nwindows <= 1\)$`, "gf writing the buffer first")
	})
	e.InFunction("do_bang", func(e *E) {
		e.Cut(`(?m)^[ \t]*if \(addr_count == 0\)\n[ \t]*\{\n[ \t]*msg_scroll = FALSE;\n[ \t]*autowrite_all\(\);\n[ \t]*msg_scroll = scroll_save;\n[ \t]*\}\n\n?`, 1, ":! writing all buffers first")
	})
	e.InFunction("ex_stop", func(e *E) {
		e.Cut(`(?m)^[ \t]*if \(!eap->forceit\)\n[ \t]*\{\n[ \t]*autowrite_all\(\);\n[ \t]*\}\n`, 1, ":stop writing all buffers first")
	})
	e.LiteralN("(p_awa ? CCGD_AW : 0) | ", "", 3, "'autowriteall' asking check_changed to write")
	e.LiteralN("CCGD_AW | ", "", 2, ":next and the argument list asking check_changed to autowrite")

	// 'buftype'
	e.InFunction("fileinfo", func(e *E) {
		e.Literal("(curbuf->b_flags & BF_NOTEDITED) && !bt_dontwrite(curbuf) ?", "(curbuf->b_flags & BF_NOTEDITED) ?", "[Not edited] shown only for a writable 'buftype'")
		e.Literal("(curbuf->b_flags & BF_NEW) && !bt_dontwrite(curbuf) ?", "(curbuf->b_flags & BF_NEW) ?", "[New] shown only for a writable 'buftype'")
	})
	e.InFunction("buf_write", func(e *E) {
		e.Literal(" && !bt_nofilename(buf)", "", "a first :w naming the buffer unless 'buftype' forbids it")
		e.FoldNeverRepeat(`(?m)^[ \t]*if \(overwriting && bt_nofilename\(curbuf\)\)$`, 3, "writing a no-file buffer refused")
		e.FoldNeverRepeat(`(?m)^[ \t]*if \(nofile_err\)$`, 2, "the no-file refusal reported")
		e.Literal(" || did_cmd || nofile_err)", " || did_cmd)", "an autocommand check waiting on the no-file refusal")
	})
	e.InFunction("buf_copy_options", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(buf->b_p_bt\[0\] == 'h'\)$`, "a help buffer's 'buftype' cleared on copy")
	})
	e.InFunction("changed", func(e *E) {
		e.Literal("if (curbuf->b_may_swap && !bt_dontwrite(curbuf))", "if (curbuf->b_may_swap)", "the swap file opened only for a writable 'buftype'")
	})
	e.InFunction("readfile", func(e *E) {
		e.FoldAlwaysRepeat(`(?m)^[ \t]*if \(!bt_dontwrite\(curbuf\)\)$`, 2, "reading checking for a swap file only for a writable 'buftype'")
	})
	e.InFunction("open_buffer", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(bt_nofileread\(curbuf\)\)$`, "a no-file 'buftype' skipping the read")
	})
	e.InFunction("do_write", func(e *E) {
		e.Literal("(bt_dontwrite_msg(curbuf) || check_fname() == FAIL", "(check_fname() == FAIL", ":w refused for 'buftype'")
	})
	e.InFunction("check_overwrite", func(e *E) {
		e.Literal("!bt_nofilename(buf) && ", "", "the overwrite check skipping a no-file buffer")
	})
	e.InFunction("shorten_buf_fname", func(e *E) {
		e.Literal(" && !bt_nofilename(buf)", "", "a no-file buffer's name not shortened")
	})
	e.InFunction("buf_spname", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(bt_nofilename\(buf\)\)$`, "[Scratch] for a no-file buffer")
	})
	e.InFunction("edit", func(e *E) {
		e.Literal("if (!bt_prompt(curwin->w_buffer) && stop_insert_mode)", "if (stop_insert_mode)", "leaving Insert mode differently in a prompt buffer")
	})
	e.InFunction("bufIsChangedNotTerm", func(e *E) {
		e.Sub(`return \(!bt_dontwrite\(buf\) \|\| bt_prompt\(buf\)\)\s*&& \(buf->b_changed\);`, "return buf->b_changed;", 1, "a changed buffer judged by 'buftype'")
	})

	// 'jumpoptions'
	e.InFunction("setpcmark", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(jop_flags & JOP_STACK\)$`, "the jump list as a stack")
	})
	e.InFunction("cleanup_jumplist", func(e *E) {
		e.Literal("mustfree = !(jop_flags & JOP_STACK);", "mustfree = TRUE;", "duplicate jumps kept for a stack")
	})
	e.InFunction("didset_string_options", func(e *E) {
		e.Cut(`(?m)^[ \t]*\(void\)opt_strings_flags\(p_jop, p_jop_values, &jop_flags, TRUE\);\n`, 1, "startup parsing 'jumpoptions'")
	})

	// 'updatetime': the idle wait did nothing, so it goes
	e.InFunction("inchar_loop", func(e *E) {
		e.Literal("if (wtime < 0 && did_start_blocking)", "if (wtime < 0)", "a wait with no timeout blocking at once")
		e.Sub(`(?m)^([ \t]*)if \(wtime >= 0\)\n[ \t]*\{\n[ \t]*wait_time = wtime - elapsed_time;\n[ \t]*\}\n[ \t]*else\n[ \t]*\{\n[ \t]*wait_time = p_ut - elapsed_time;\n[ \t]*\}\n`,
			"${1}wait_time = wtime - elapsed_time;\n", 1, "the 'updatetime' idle timeout")
		// The expired-wait block is replaced by its own head plus `return 0;`.
		// It is matched by its ENDS rather than by one pattern: the body is
		// CursorHold handling that has nothing in common with the test above it.
		if !e.Failed() {
			t := e.Text()
			m := expiredWait.FindSubmatchIndex(t)
			if m == nil {
				e.Refuse("inchar_loop -- the expired-wait test was not found")
				return
			}
			ind := string(t[m[2]:m[3]])
			tail := fmt.Sprintf("\n%s    before_blocking();\n%s    continue;\n%s}\n", ind, ind, ind)
			z := bytes.Index(t[m[1]:], []byte(tail))
			if z < 0 || bytes.Count(t, []byte(tail)) != 1 {
				e.Refuse("inchar_loop -- the expired-wait block does not end in before_blocking(); continue;")
				return
			}
			z += m[1]
			head := fmt.Sprintf("%sif (wait_time <= 0 && did_call_wait_func)\n%s{\n%s    return 0;\n%s}\n", ind, ind, ind, ind)
			out := append([]byte{}, t[:m[0]]...)
			out = append(out, head...)
			e.Set(append(out, t[z+len(tail):]...))
			e.say("CursorHold and before_blocking() after the idle wait")
		}
		// Blocking now starts on the first wait with no timeout, so by the time
		// the loop's exit test runs for one, it has blocked: did_start_blocking
		// was TRUE there, and an interrupted indefinite wait must still return 0
		// rather than block again.
		e.Literal(" || (wtime < 0 && !did_start_blocking))", ")", "an interrupted indefinite wait returning instead of blocking again")
	})
	e.InFunction("gotchars", func(e *E) {
		e.Cut(`(?m)^[ \t]*for \(i = 0; i < state\.buflen; \+\+i\)\n[ \t]*\{\n[ \t]*updatescript\(state\.buf\[i\]\);\n[ \t]*\}\n\n?`, 1, "typed characters passed to a script file and a swap sync that are both gone")
	})
	e.InFunction("wait_return", func(e *E) {
		for _, line := range []string{"save_scriptout = scriptout;", "scriptout = NULL;", "scriptout = save_scriptout;"} {
			e.Cut(`(?m)^[ \t]*`+regexp.QuoteMeta(line)+`\n`, 1, "wait_return saving and restoring a script file that is never open")
		}
	})
	e.InFunction("check_num_option_bounds", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(p_ut < 0\)$`, "'updatetime' kept non-negative")
	})

	// 'buflisted'
	e.InFunction("buf_freeall", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(\(flags & BFA_DEL\) && buf->b_p_bl\)$`, "BufDelete for a listed buffer")
	})
	e.InFunction("buflist_findpat", func(e *E) {
		e.Literal("buf->b_p_bl == find_listed && ", "find_listed && ", "a buffer search telling listed from unlisted")
	})
	e.InFunction("buflist_new", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(\(flags & BLN_LISTED\) && !buf->b_p_bl\)$`, "an existing buffer becoming listed")
		e.Cut(`(?m)^[ \t]*buf->b_p_bl = \(flags & BLN_LISTED\) \? TRUE : FALSE;\n`, 1, "a new buffer recording whether it is listed")
		e.DropIf(`(?m)^[ \t]*if \(flags & BLN_LISTED\)$`, "BufAdd for a new listed buffer")
	})
	e.InFunction("close_buffer", func(e *E) {
		e.Cut(`(?m)^[ \t]*if \(del_buf\)\n[ \t]*\{\n[ \t]*buf->b_p_bl = FALSE;\n[ \t]*\}\n`, 1, "a deleted buffer becoming unlisted")
	})
	e.InFunction("set_rw_fname", func(e *E) {
		e.FoldNeverRepeat(`(?m)^[ \t]*if \(curbuf->b_p_bl\)$`, 2, "BufDelete and BufAdd around a renamed listed buffer")
	})
	e.InFunction("do_ecmd", func(e *E) {
		e.Cut(`(?m)^[ \t]*else\n[ \t]*\{\n[ \t]*if \(!curbuf->b_help\)\n[ \t]*\{\n[ \t]*set_buflisted\(TRUE\);\n[ \t]*\}\n[ \t]*\}\n`, 1, "an edited buffer becoming listed")
	})
	e.Cut(`(?m)^[ \t]*set_buflisted\((?:TRUE|FALSE)\);\n`, 3, "stdin, startup and help buffers setting whether they are listed")

	// 'filetype'
	e.InFunction("enter_buffer", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(\*curbuf->b_p_ft == NUL\)$`, "entering a buffer with no 'filetype' forgetting FileType")
	})
	e.InFunction("do_ecmd", func(e *E) {
		e.Cut(`(?m)^[ \t]*curbuf->b_did_filetype = false;\n\n?`, 1, ":edit forgetting FileType")
	})
	e.InFunction("readfile", func(e *E) {
		e.Cut(`(?m)^[ \t]*curbuf->b_au_did_filetype = false;\n\n?`, 1, "reading forgetting FileType")
		e.DropIf(`(?m)^[ \t]*if \(!curbuf->b_au_did_filetype && \*curbuf->b_p_ft != NUL\)$`, "reading firing FileType")
	})
	e.InFunction("did_set_string_option", func(e *E) {
		e.FoldNever(`(?m)^[ \t]*else if \(varp == &\(curbuf->b_p_ft\)\)$`, ":set ft= firing FileType")
	})
	e.InFunction("fix_help_buffer", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \( strcmp\(\(char \*\)\(curbuf->b_p_ft\), \(char \*\)\("help"\)\)  != 0\)$`, "a help buffer setting 'filetype' to help")
	})
	return e.Done()
}

// Whim62BL takes 'buflisted”s field and its get_varp case.  A second entry,
// standing where its heredoc stood.
func Whim62BL(text []byte, w io.Writer) ([]byte, error) {
	e := New("nobufopts", text, w)
	fieldPat := `(?m)^[ \t]*int[ \t]+b_p_bl;\n`
	casePat := `(?m)^[ \t]*case[^\n]*\bBV_BL\b[^\n]*\n[ \t]*return \(char_u \*\)&\(curbuf->b_p_bl\);\n`
	a := len(regexp.MustCompile(fieldPat).FindAll(e.Text(), -1))
	b := len(regexp.MustCompile(casePat).FindAll(e.Text(), -1))
	if a != 1 || b != 1 {
		e.Refuse("b_p_bl's field and get_varp case matched %d and %d times, expected 1 and 1", a, b)
		return e.Done()
	}
	e.Set(regexp.MustCompile(casePat).ReplaceAll(regexp.MustCompile(fieldPat).ReplaceAll(e.Text(), nil), nil))
	e.say("'buflisted''s field and get_varp case removed")
	return e.Done()
}

func init() {
	register("whim62", Whim62)
	register("whim62bl", Whim62BL)
}
