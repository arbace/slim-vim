package cut

import (
	"fmt"
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

// nwBreak is `{ break; }` as the expander leaves it.
const nwBreak = `[ \t]*\{\n[ \t]*break;\n[ \t]*\}\n`

const cmdwinPlain = `^[ \t]*if \(cmdwin_type != 0\)$`

var (
	nwSplitMod  = regexp.MustCompile(`cmod->cmod_split \|=`)
	nwNvWindow  = regexp.MustCompile(`\{Ctrl_W, nv_window`)
	nwDobufSpl  = regexp.MustCompile(`\bDOBUF_SPLIT\b`)
	nwWindoName = regexp.MustCompile(`\bCMD_windo\b`)
	nwTableRow  = regexp.MustCompile(`^[ \t]*\[?CMD_`)
)

// foldCount folds a condition that is now always false, `count` times.
func (e ed) foldCount(seg []byte, pattern, what string, count int) ([]byte, error) {
	out, err := cutil.FoldNever(seg, "(?m)"+pattern, count)
	if err != nil {
		return nil, fmt.Errorf("%s: %s -- %v", e.tool, what, err)
	}
	e.say(what)
	return out, nil
}

// dropIfPlain is DropIf with no count assertion, matching the Python's own
// helper here.
func (e ed) dropIfPlain(seg []byte, pattern, what string) ([]byte, error) {
	out, err := cutil.DropIf(seg, "(?m)"+pattern, 1)
	if err != nil {
		return nil, fmt.Errorf("%s: %s -- %v", e.tool, what, err)
	}
	e.say(what)
	return out, nil
}

// NoWindows leaves one window: nothing makes, reaches, resizes or binds a
// second.
func NoWindows(text []byte, w io.Writer) ([]byte, error) {
	e := ed{"nowindows", w}
	var err error

	text, err = e.inFunction(text, "parse_command_modifiers", func(s []byte) ([]byte, error) {
		var err error
		for _, m := range []struct{ pat, repl, what string }{
			{`^[ \t]*case 'a':\n[ \t]*if \(!checkforcmd_noparen\(&eap->cmd, "aboveleft", 3\)\)\n` + nwBreak +
				`[ \t]*cmod->cmod_split \|= WSP_ABOVE;\n[ \t]*continue;\n\n`, "", ":aboveleft"},
			{`^[ \t]*case 'b':\n[ \t]*if \(checkforcmd_noparen\(&eap->cmd, "belowright", 3\)\)\n` +
				`[ \t]*\{\n[ \t]*cmod->cmod_split \|= WSP_BELOW;\n[ \t]*continue;\n[ \t]*\}\n` +
				`[ \t]*if \(!checkforcmd_noparen\(&eap->cmd, "botright", 2\)\)\n` + nwBreak +
				`[ \t]*cmod->cmod_split \|= WSP_BOT;\n[ \t]*continue;\n\n`, "",
				":belowright and :botright"},
			{`^[ \t]*if \(checkforcmd_noparen\(&eap->cmd, "horizontal", 3\)\)\n` +
				`[ \t]*\{\n[ \t]*cmod->cmod_split \|= WSP_HOR;\n[ \t]*continue;\n[ \t]*\}\n`, "",
				":horizontal"},
			{`^([ \t]*)if \(!checkforcmd_noparen\(&eap->cmd, "leftabove", 5\)\)\n` + nwBreak +
				`[ \t]*cmod->cmod_split \|= WSP_ABOVE;\n[ \t]*continue;\n`, "${1}break;\n", ":leftabove"},
			{`^[ \t]*case 'r':\n[ \t]*if \(!checkforcmd_noparen\(&eap->cmd, "rightbelow", 6\)\)\n` + nwBreak +
				`[ \t]*cmod->cmod_split \|= WSP_BELOW;\n[ \t]*continue;\n\n`, "", ":rightbelow"},
			{`^[ \t]*case 't':\n[ \t]*if \(!checkforcmd_noparen\(&eap->cmd, "topleft", 2\)\)\n` + nwBreak +
				`[ \t]*cmod->cmod_split \|= WSP_TOP;\n[ \t]*continue;\n\n`, "", ":topleft"},
			{`^[ \t]*if \(checkforcmd_noparen\(&eap->cmd, "vertical", 4\)\)\n` +
				`[ \t]*\{\n[ \t]*cmod->cmod_split \|= WSP_VERT;\n[ \t]*continue;\n[ \t]*\}\n`, "",
				":vertical"},
		} {
			if s, err = e.subCountRepl(s, "(?m)"+m.pat, m.repl, m.what, 1); err != nil {
				return nil, err
			}
		}
		return s, nil
	})
	if err != nil {
		return nil, err
	}

	if text, err = e.inFunction(text, "has_cmdmod", func(s []byte) ([]byte, error) {
		return e.literal(s, "            || cmod->cmod_split != 0\n", "",
			"has_cmdmod counting a split modifier", 1)
	}); err != nil {
		return nil, err
	}

	// A ROW IS NEVER DELETED FROM nv_cmds[], IT IS POINTED AT nv_error.
	if text, err = e.subCountRepl(text, `(?m)^([ \t]*\{Ctrl_W, )nv_window(, 0, 0\} ,)$`,
		"${1}nv_error${2}", "CTRL-W's row points at nv_error", 1); err != nil {
		return nil, err
	}

	if text, err = e.inFunction(text, "nv_record", func(s []byte) ([]byte, error) {
		return e.foldNever(s,
			`^[ \t]*if \(cap->nchar == ':' \|\| cap->nchar == '/' \|\| cap->nchar == '\?'\)$`,
			"q: q/ q? opening it")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "getcmdline_int", func(s []byte) ([]byte, error) {
		return e.foldNever(s, `^[ \t]*if \(c == cedit_key \|\| c == [^\n]*KE_CMDWIN[^\n]*\)$`,
			"CTRL-F on the command line opening it")
	}); err != nil {
		return nil, err
	}
	for _, name := range []string{"ex_quit", "before_quit_all", "ex_exit", "text_locked",
		"get_text_locked_msg", "nv_normal"} {
		name := name
		if text, err = e.inFunction(text, name, func(s []byte) ([]byte, error) {
			return e.foldNever(s, cmdwinPlain, name+" asking whether it is open")
		}); err != nil {
			return nil, err
		}
	}
	if text, err = e.inFunction(text, "edit", func(s []byte) ([]byte, error) {
		var err error
		for _, f := range []struct{ pat, what string }{
			{`^[ \t]*if \(c == Ctrl_C && cmdwin_type != 0\)$`, "insert-mode CTRL-C closing it"},
			{cmdwinPlain, "insert-mode Enter executing it"},
			{`^[ \t]*if \(curwin-> w_onebuf_opt\.wo_scb \)$`, "insert mode's 'scrollbind'"},
			{`^[ \t]*if \(curwin-> w_onebuf_opt\.wo_crb \)$`, "insert mode's 'cursorbind'"},
		} {
			if s, err = e.foldNever(s, f.pat, f.what); err != nil {
				return nil, err
			}
		}
		return s, nil
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "do_one_cmd", func(s []byte) ([]byte, error) {
		return e.foldNever(s, `^[ \t]*if \(cmdwin_type != 0 && !\(ea\.argt & EX_CMDWIN\)\)$`,
			"commands refused inside it")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "goto_tabpage_tp", func(s []byte) ([]byte, error) {
		return e.dropIfPlain(s,
			`^[ \t]*if \(trigger_enter_autocmds \|\| trigger_leave_autocmds\)$`,
			"goto_tabpage_tp refusing inside it")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "nv_down", func(s []byte) ([]byte, error) {
		return e.foldNever(s, `^[ \t]*if \(cmdwin_type != 0 && cap->cmdchar == CAR\)$`,
			"normal-mode Enter executing it")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "nv_esc", func(s []byte) ([]byte, error) {
		s, err := e.literal(s, "cmdwin_type == 0 && ", "",
			"nv_esc asking before the abandon hint", 1)
		if err != nil {
			return nil, err
		}
		if s, err = e.foldNever(s, cmdwinPlain, "normal-mode Esc closing it"); err != nil {
			return nil, err
		}
		return e.foldNever(s,
			`^[ \t]*else if \(cmdwin_type != 0 && ex_normal_busy && typebuf_was_empty\)$`,
			":normal Esc closing it")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "vgetorpeek", func(s []byte) ([]byte, error) {
		var err error
		for _, l := range []struct{ old, what string }{
			{" || (cmdwin_type > 0 && tc == ESC)", "an interrupted Esc closing it"},
			// tc remembered the previous key for that test alone.
			{"                    static int tc = 0;\n", "vgetorpeek declaring the previous key"},
			{"                    tc = c;\n", "vgetorpeek remembering it"},
		} {
			if s, err = e.literal(s, l.old, "", l.what, 1); err != nil {
				return nil, err
			}
		}
		return s, nil
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "do_ecmd", func(s []byte) ([]byte, error) {
		s, err := e.literal(s, "            int         save_cmdwin_type = cmdwin_type;\n"+
			"            win_T       *save_cmdwin_win = cmdwin_win;\n\n"+
			"            cmdwin_type = 0;\n            cmdwin_win = NULL;\n", "",
			"do_ecmd hiding it", 1)
		if err != nil {
			return nil, err
		}
		return e.literal(s, "            cmdwin_type = save_cmdwin_type;\n"+
			"            cmdwin_win = save_cmdwin_win;\n\n", "", "do_ecmd restoring it", 1)
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "win_line", func(s []byte) ([]byte, error) {
		return e.foldNever(s, `^[ \t]*if \(wp == cmdwin_win\)$`, "its column drawn")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "win_col_off", func(s []byte) ([]byte, error) {
		return e.literal(s, " + (wp != cmdwin_win ? 0 : 1)", "", "its column counted", 1)
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "buf_spname", func(s []byte) ([]byte, error) {
		return e.foldNever(s, `^[ \t]*if \(buf == cmdwin_buf\)$`, "its buffer name")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "comp_textwidth", func(s []byte) ([]byte, error) {
		return e.foldNever(s, `^[ \t]*if \(curbuf == cmdwin_buf\)$`, "its textwidth")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "main_loop", func(s []byte) ([]byte, error) {
		return e.literal(s, "while (!cmdwin || cmdwin_result == 0)", "while (!cmdwin)",
			"main_loop waiting for its result", 1)
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "didset_options", func(s []byte) ([]byte, error) {
		return e.literal(s, "    (void)did_set_cedit(NULL);\n", "",
			"startup reading 'cedit'", 1)
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "check_num_option_bounds", func(s []byte) ([]byte, error) {
		return e.dropIfPlain(s, `^[ \t]*if \(p_cwh < 1\)$`, "'cmdwinheight' clamped")
	}); err != nil {
		return nil, err
	}

	if text, err = e.inFunction(text, "command_line_scan", func(s []byte) ([]byte, error) {
		s, held, err := DropShort(s, 0, map[string]bool{"o": true, "O": true})
		if err != nil {
			return nil, err
		}
		if !setEqual(held, "o", "O") {
			return nil, fmt.Errorf("nowindows: -o and -O are not both labels in the option "+
				"switch: %s", pyList(sortedKeys(held)))
		}
		fmt.Fprintln(w, "  nowindows    -o and -O are unknown options")
		return s, nil
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "create_windows", func(s []byte) ([]byte, error) {
		var err error
		if s, err = e.dropIfPlain(s, `^[ \t]*if \(parmp->window_count == -1\)$`,
			"create_windows defaulting the count"); err != nil {
			return nil, err
		}
		if s, err = e.dropIfPlain(s, `^[ \t]*if \(parmp->window_count == 0\)$`,
			"create_windows counting the files"); err != nil {
			return nil, err
		}
		if s, err = e.foldNever(s, `^[ \t]*if \(parmp->window_count > 1\)$`,
			"create_windows making a window per file"); err != nil {
			return nil, err
		}
		return e.literal(s, "    parmp->window_count = 1;\n", "",
			"create_windows settling on one", 1)
	}); err != nil {
		return nil, err
	}
	if text, err = e.subOnce(text, `^[ \t]+edit_buffers\([^\n]*\);\n`,
		"startup editing a file in each window"); err != nil {
		return nil, err
	}
	if text, err = e.literal(text, "    params.window_count = -1;\n", "",
		"main initialising the window count", 1); err != nil {
		return nil, err
	}

	if text, err = e.subCount(text,
		`^[ \t]*\((?:curwin|wp)\)-> w_onebuf_opt\.wo_(?:scb|crb)  = FALSE;\n`,
		"every assignment of 'scrollbind' and 'cursorbind'", 18); err != nil {
		return nil, err
	}
	for _, v := range []struct{ wv, fld string }{
		{"SCBIND", "scb"}, {"CRBIND", "crb"}, {"WFB", "wfb"},
	} {
		if text, err = e.subOnce(text,
			`^[ \t]*case   \(idopt_T\)\(PV_WIN \+ \(int\)\(WV_`+v.wv+`\)\)  :\n`+
				`[ \t]*return \(char_u \*\)&\(curwin-> w_onebuf_opt\.wo_`+v.fld+` \);\n`,
			"get_varp for WV_"+v.wv); err != nil {
			return nil, err
		}
	}
	for _, l := range []struct{ old, what string }{
		{"    to->wo_scb = from->wo_scb;\n    to->wo_scb_save = from->wo_scb_save;\n",
			"copy_winopt copying 'scrollbind'"},
		{"    to->wo_crb = from->wo_crb;\n    to->wo_crb_save = from->wo_crb_save;\n",
			"copy_winopt copying 'cursorbind'"},
	} {
		if text, err = e.literal(text, l.old, "", l.what, 1); err != nil {
			return nil, err
		}
	}
	if text, err = e.inFunction(text, "normal_cmd", func(s []byte) ([]byte, error) {
		s, err := e.foldNever(s, `^[ \t]*if \(curwin-> w_onebuf_opt\.wo_scb  && toplevel\)$`,
			"normal mode's 'scrollbind'")
		if err != nil {
			return nil, err
		}
		return e.foldNever(s, `^[ \t]*if \(curwin-> w_onebuf_opt\.wo_crb  && toplevel\)$`,
			"normal mode's 'cursorbind'")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "ex_substitute", func(s []byte) ([]byte, error) {
		return e.foldNever(s, `^[ \t]*if \(curwin-> w_onebuf_opt\.wo_crb \)$`, ":s's 'cursorbind'")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "set_shellsize_inner", func(s []byte) ([]byte, error) {
		return e.foldNever(s, `^[ \t]*if \(curwin-> w_onebuf_opt\.wo_scb \)$`,
			"a resize's 'scrollbind'")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "scroll_to_fraction", func(s []byte) ([]byte, error) {
		return e.literal(s, "(!wp-> w_onebuf_opt.wo_scb  || wp == curwin) && ", "",
			"scroll_to_fraction's 'scrollbind'", 1)
	}); err != nil {
		return nil, err
	}
	for _, name := range []string{"check_can_set_curbuf_disabled", "check_can_set_curbuf_forceit"} {
		name := name
		if text, err = e.inFunction(text, name, func(s []byte) ([]byte, error) {
			return e.foldNever(s,
				`^[ \t]*if \((?:!forceit && )?curwin-> w_onebuf_opt\.wo_wfb \)$`,
				name+"'s 'winfixbuf'")
		}); err != nil {
			return nil, err
		}
	}

	if text, err = e.inFunction(text, "ex_drop", func(s []byte) ([]byte, error) {
		s, err := e.literal(s, "    int         split = FALSE;\n", "",
			":drop declaring its fallback", 1)
		if err != nil {
			return nil, err
		}
		if s, err = e.dropIfPlain(s, `^[ \t]*if \(!buf_hide\(curbuf\)\)$`,
			":drop asking whether to split"); err != nil {
			return nil, err
		}
		return e.foldNever(s, `^[ \t]*if \(split\)$`, ":drop splitting")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "do_argfile", func(s []byte) ([]byte, error) {
		s, err := e.literal(s, "    int is_split_cmd = *eap->cmd == 's';\n", "",
			"do_argfile asking for a split", 1)
		if err != nil {
			return nil, err
		}
		if s, err = e.literal(s, "!is_split_cmd && ", "",
			"do_argfile checking the buffer can go", 1); err != nil {
			return nil, err
		}
		return e.foldNever(s, `^[ \t]*if \(is_split_cmd\)$`, "do_argfile splitting")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "goto_buffer", func(s []byte) ([]byte, error) {
		s, err := e.subCount(s, `^[ \t]*case CMD_(?:sbnext|sbNext|sbprevious):\n`,
			"goto_buffer naming :sb commands", 3)
		if err != nil {
			return nil, err
		}
		if s, err = e.literal(s, `*eap->cmd == 's' ? DOBUF_SPLIT : DOBUF_GOTO`, "DOBUF_GOTO",
			"goto_buffer choosing a split", 1); err != nil {
			return nil, err
		}
		return e.foldNever(s,
			`^[ \t]*if \(swap_exists_action == SEA_QUIT && \*eap->cmd == 's'\)$`,
			"goto_buffer closing the split")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "do_buffer_ext", func(s []byte) ([]byte, error) {
		s, err := e.literal(s, "(action == DOBUF_GOTO || action == DOBUF_SPLIT)",
			"action == DOBUF_GOTO", "do_buffer_ext refusing a dummy buffer", 1)
		if err != nil {
			return nil, err
		}
		for _, f := range []struct{ pat, what string }{
			{`^[ \t]*if \(action == DOBUF_SPLIT && swbuf_goto_win_with_buf\(buf\) != NULL\)$`,
				"do_buffer_ext's 'switchbuf'"},
			{`^[ \t]*if \(action == DOBUF_SPLIT && win_split\(0, 0\) == FAIL\)$`,
				"do_buffer_ext splitting"},
			{`^[ \t]*if \(action == DOBUF_SPLIT\)$`, "do_buffer_ext unbinding the split"},
		} {
			if s, err = e.foldNever(s, f.pat, f.what); err != nil {
				return nil, err
			}
		}
		return s, nil
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "buflist_getfile", func(s []byte) ([]byte, error) {
		return e.dropIfPlain(s, `^[ \t]*if \(options & GETF_SWITCH\)$`,
			"buflist_getfile's 'switchbuf'")
	}); err != nil {
		return nil, err
	}
	if text, err = e.literal(text,
		"    (void)opt_strings_flags(p_swb, p_swb_values, &swb_flags, TRUE);\n", "",
		"didset_string_options reading 'switchbuf'", 1); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "ex_listdo", func(s []byte) ([]byte, error) {
		var err error
		if s, err = e.foldNever(s,
			`^[ \t]*if \(curwin-> w_onebuf_opt\.wo_wfb  && eap->cmdidx != CMD_windo\)$`,
			"ex_listdo's 'winfixbuf'"); err != nil {
			return nil, err
		}
		if s, err = e.literal(s, "eap->cmdidx == CMD_windo || ", "",
			":windo skipping the changed-buffer check", 1); err != nil {
			return nil, err
		}
		if s, err = e.subOnce(s,
			`^[ \t]*wp = firstwin;\n[ \t]*switch \(eap->cmdidx\)\n[ \t]*\{\n[ \t]*case CMD_windo:\n`+
				`[ \t]*for \( ; wp != NULL && i \+ 1 < eap->line1; wp = wp->w_next\)\n[ \t]*\{\n[ \t]*i\+\+;\n`+
				`[ \t]*\}\n[ \t]*break;\n[ \t]*default:\n[ \t]*break;\n[ \t]*\}\n`,
			":windo's starting window"); err != nil {
			return nil, err
		}
		if s, err = e.foldCount(s, `^[ \t]*if \(eap->cmdidx == CMD_windo\)$`,
			":windo stepping, binding and stopping", 3); err != nil {
			return nil, err
		}
		for _, l := range []struct{ old, what string }{
			{"    int         i;\n    win_T       *wp;\n", "ex_listdo declaring its counters"},
			{"        i = 0;\n", "ex_listdo starting the count"},
			{"            ++i;\n\n", "ex_listdo counting"},
		} {
			if s, err = e.literal(s, l.old, "", l.what, 1); err != nil {
				return nil, err
			}
		}
		return s, nil
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "set_context_by_cmdname", func(s []byte) ([]byte, error) {
		return e.subOnce(s, `^[ \t]*case CMD_windo:\n`, "completion for :windo")
	}); err != nil {
		return nil, err
	}

	var left []string
	for _, c := range []struct {
		what string
		n    int
		want int
	}{
		{"a split modifier in the parser", len(nwSplitMod.FindAll(text, -1)), 0},
		{"nv_window in the key table", len(nwNvWindow.FindAll(text, -1)), 0},
		{"DOBUF_SPLIT outside its enumerator", len(nwDobufSpl.FindAll(text, -1)), 1},
		// The Python writes this one with a NEGATIVE LOOKAHEAD; RE2 has none,
		// so it is two tests over the lines.
		{"CMD_windo outside the table", len(linesMatchingUnless(text, nwWindoName, nwTableRow)), 0},
	} {
		if c.n != c.want {
			left = append(left, fmt.Sprintf("(%s, %d)", cutil.PyRepr(c.what), c.n))
		}
	}
	if len(left) > 0 {
		return nil, fmt.Errorf("nowindows: still present: [%s]", strings.Join(left, ", "))
	}

	e.say("nothing makes, reaches, resizes or binds a second window")
	return text, nil
}
