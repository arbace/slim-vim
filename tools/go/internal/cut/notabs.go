package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

var tpWord = regexp.MustCompile(`\btp\b`)
var cmodTab = regexp.MustCompile(`\bcmod_tab\b`)

// notabsBody replaces a definition's body, scoped to its own span.
func notabsBody(text []byte, name, newBody string) ([]byte, error) {
	a, z, ok := cutil.FindDefinition(text, cutil.Blank(text), name)
	if !ok {
		return nil, fmt.Errorf("notabs: %s is not defined at file scope", name)
	}
	seg := text[a:z]
	b := cutil.Blank(seg)
	o := bytes.IndexByte(b, '{')
	c := cutil.Match(b, o)
	if o < 0 || c < 0 {
		return nil, fmt.Errorf("notabs: %s is unbalanced", name)
	}
	out := make([]byte, 0, len(text))
	out = append(out, text[:a]...)
	out = append(out, seg[:o]...)
	out = append(out, "{\n"...)
	out = append(out, newBody...)
	out = append(out, '}')
	out = append(out, seg[c+1:]...)
	return append(out, text[z:]...), nil
}

// NoTabs removes tab pages: nothing makes or reaches a second one.
func NoTabs(text []byte, w io.Writer) ([]byte, error) {
	e := ed{"notabs", w}
	var err error

	const tabMod = `(?m)^[ \t]*if \(checkforcmd_noparen\(&p, "tab", 3\)\)$`
	if n := len(regexp.MustCompile(tabMod).FindAll(text, -1)); n != 1 {
		return nil, fmt.Errorf("notabs: the :tab modifier is not where this expects")
	}
	if text, err = cutil.DropIf(text, tabMod, 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  notabs       the :tab modifier")

	for _, b := range []struct{ name, body string }{
		{"tabline_height", "    return 0;\n"},
		{"draw_tabline", "    redraw_tabline = FALSE;\n"},
	} {
		if text, err = notabsBody(text, b.name, b.body); err != nil {
			return nil, err
		}
	}
	fmt.Fprintln(w, "  notabs       the tab line is 0 lines and draws nothing")

	// A stub answers the question; it does not remove the caller.  win_split()
	// asked may_open_tabpage() whether a :tab-modified split had become a tab
	// page, and nothing can modify one now -- so the question goes, and the
	// sweep takes the function.
	if text, err = e.inFunction(text, "win_split", func(s []byte) ([]byte, error) {
		return e.foldNever(s, `^[ \t]*if \(may_open_tabpage\(\) == OK\)$`,
			"win_split opening a tab page for :tab")
	}); err != nil {
		return nil, err
	}

	for _, l := range []struct{ old, new, what string }{
		{"is_split_cmd || cmdmod.cmod_tab != 0", "is_split_cmd",
			":argedit and friends testing for :tab"},
		{"            || cmod->cmod_tab != 0\n", "", "has_cmdmod counting :tab"},
		{" && cmdmod.cmod_tab == 0)", ")", "CTRL-W's 'switchbuf' test for :tab"},
		{"    cmdmod.cmod_tab = 0;\n    cmdmod.cmod_flags |= CMOD_NOSWAPFILE;\n",
			"    cmdmod.cmod_flags |= CMOD_NOSWAPFILE;\n",
			"the command-line window clearing :tab"},
	} {
		if text, err = e.literal(text, l.old, l.new, l.what, 1); err != nil {
			return nil, err
		}
	}
	if text, err = e.foldNever(text, `^[ \t]*if \(cmdmod\.cmod_tab\)$`, ":drop under :tab"); err != nil {
		return nil, err
	}
	for _, l := range []struct{ old, what string }{
		{"        postponed_split_tab = cmdmod.cmod_tab;\n", ":wincmd passing :tab on"},
		{"        postponed_split_tab = 0;\n", ":wincmd clearing it"},
	} {
		if text, err = e.literal(text, l.old, "", l.what, 1); err != nil {
			return nil, err
		}
	}

	if text, err = e.inFunction(text, "ex_buffer_all", func(s []byte) ([]byte, error) {
		var err error
		if s, err = e.foldNever(s, `^[ \t]*if \(had_tab > 0\)$`,
			":ball starting at the first tab page"); err != nil {
			return nil, err
		}
		if s, err = e.literal(s, " || (had_tab > 0 && wp != firstwin))", ")",
			":ball closing windows for tab pages", 1); err != nil {
			return nil, err
		}
		if s, err = e.foldAlways(s, `^[ \t]*if \(had_tab == 0 \|\| tpnext == NULL\)$`,
			":ball stopping after one tab page"); err != nil {
			return nil, err
		}
		if s, err = e.foldNever(s, `^[ \t]*if \(had_tab != 0\)$`,
			":ball opening tab pages"); err != nil {
			return nil, err
		}
		if s, err = e.foldNever(s,
			`^[ \t]*if \(had_tab > 0 && tabpage_index\(NULL\) <= p_tpm\)$`,
			":ball's 'tabpagemax'"); err != nil {
			return nil, err
		}
		return e.literal(s, "    int         had_tab = cmdmod.cmod_tab;\n", "",
			":ball remembering :tab", 1)
	}); err != nil {
		return nil, err
	}

	if text, err = e.inFunction(text, "arg_all_close_unused_windows", func(s []byte) ([]byte, error) {
		var err error
		if s, err = e.foldNever(s, `^[ \t]*if \(aall->had_tab > 0\)$`,
			":all starting at the first tab page"); err != nil {
			return nil, err
		}
		if s, err = e.literal(s, "(first_tabpage->tp_next == NULL || !aall->had_tab)", "TRUE",
			":all deciding whether a last window may go", 1); err != nil {
			return nil, err
		}
		return e.foldAlways(s, `^[ \t]*if \(aall->had_tab == 0 \|\| tpnext == NULL\)$`,
			":all stopping after one tab page")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "arg_all_open_windows", func(s []byte) ([]byte, error) {
		return e.foldNever(s,
			`^[ \t]*if \(aall->had_tab > 0 && tabpage_index\(NULL\) <= p_tpm\)$`,
			":all's 'tabpagemax'")
	}); err != nil {
		return nil, err
	}
	if text, err = e.literal(text, "    aall.had_tab = cmdmod.cmod_tab;\n", "",
		":all remembering :tab", 1); err != nil {
		return nil, err
	}

	if text, err = e.inFunction(text, "ex_splitview", func(s []byte) ([]byte, error) {
		s, err := e.literal(s, `    int         use_tab = eap->cmdidx == CMD_tabedit
                       || eap->cmdidx == CMD_tabfind
                       || eap->cmdidx == CMD_tabnew;
`, "", "ex_splitview asking whether this is a tab command", 1)
		if err != nil {
			return nil, err
		}
		return e.foldNever(s, `^[ \t]*if \(use_tab\)$`, "ex_splitview opening a tab page")
	}); err != nil {
		return nil, err
	}
	if text, err = e.literal(text,
		" || eap->cmdidx == CMD_tabnew || eap->cmdidx == CMD_tabedit || eap->cmdidx == CMD_vnew)",
		" || eap->cmdidx == CMD_vnew)",
		":tabnew and :tabedit with no file in do_exedit", 1); err != nil {
		return nil, err
	}
	if text, err = e.foldNever(text,
		`^[ \t]*if \(close_disallowed == 0 && cmd == CMD_tabnew\)$`,
		"window_layout_locked naming :tabnew"); err != nil {
		return nil, err
	}

	if text, err = e.inFunction(text, "ex_listdo", func(s []byte) ([]byte, error) {
		var err error
		for _, l := range []struct{ old, new, what string }{
			{"eap->cmdidx != CMD_windo && eap->cmdidx != CMD_tabdo)",
				"eap->cmdidx != CMD_windo)", ":tabdo in 'winfixbuf'"},
			{"eap->cmdidx == CMD_windo || eap->cmdidx == CMD_tabdo || buf_hide",
				"eap->cmdidx == CMD_windo || buf_hide", ":tabdo needing no write"},
			{`            case CMD_tabdo:
                for ( ; tp != NULL && i + 1 < eap->line1; tp = tp->tp_next)
                {
                    i++;
                }
                break;
`, "", ":tabdo finding its first tab page"},
		} {
			if s, err = e.literal(s, l.old, l.new, l.what, 1); err != nil {
				return nil, err
			}
		}
		if s, err = e.foldNever(s, `^[ \t]*else if \(eap->cmdidx == CMD_tabdo\)$`,
			":tabdo moving to the next tab page"); err != nil {
			return nil, err
		}
		for _, l := range []struct{ old, new, what string }{
			{"if (eap->cmdidx == CMD_windo || eap->cmdidx == CMD_tabdo)",
				"if (eap->cmdidx == CMD_windo)", ":tabdo counting its range"},
			// The tab-page cursor only :tabdo read.  Set and never read is a
			// warning the sweep does not act on, so it goes here.
			{"    tabpage_T   *tp;\n", "", ":tabdo's tab-page cursor"},
			{"        tp = first_tabpage;\n", "", ":tabdo starting at the first tab page"},
		} {
			if s, err = e.literal(s, l.old, l.new, l.what, 1); err != nil {
				return nil, err
			}
		}
		if tpWord.Match(s) {
			return nil, fmt.Errorf("notabs: ex_listdo still names tp after :tabdo went")
		}
		return s, nil
	}); err != nil {
		return nil, err
	}

	if text, err = e.inFunction(text, "nv_g_cmd", func(s []byte) ([]byte, error) {
		var err error
		for _, l := range []struct{ old, new, what string }{
			{`    case 't':
        if (!checkclearop(oap))
        {
            goto_tabpage((int)cap->count0);
        }
        break;
`, `    case 't':
        if (!checkclearop(oap) && cap->count0 > 1)
        {
            beep_flush();
        }
        break;
`, "gt: a count above 1 beeps, as with one tab page"},
			{`    case 'T':
        if (!checkclearop(oap))
        {
            goto_tabpage(-(int)cap->count1);
        }
        break;
`, `    case 'T':
        (void)checkclearop(oap);
        break;
`, "gT: nothing, as with one tab page"},
			{"if (!checkclearop(oap) && goto_tabpage_lastused() == FAIL)",
				"if (!checkclearop(oap))",
				"g<Tab>: beeps, there being no last-used tab page"},
		} {
			if s, err = e.literal(s, l.old, l.new, l.what, 1); err != nil {
				return nil, err
			}
		}
		return s, nil
	}); err != nil {
		return nil, err
	}

	if text, err = e.inFunction(text, "nv_pcmark", func(s []byte) ([]byte, error) {
		return e.foldAlways(s, `^[ \t]*if \(goto_tabpage_lastused\(\) == FAIL\)$`,
			"CTRL-Tab: beeps")
	}); err != nil {
		return nil, err
	}
	if text, err = e.inFunction(text, "nv_page", func(s []byte) ([]byte, error) {
		return e.literal(s, `        if (cap->arg ==  (-1) )
        {
            goto_tabpage(-(int)cap->count1);
        }
        else
        {
            goto_tabpage((int)cap->count0);
        }
`, `        if (cap->arg !=  (-1)  && cap->count0 > 1)
        {
            beep_flush();
        }
`, "CTRL-PageUp and CTRL-PageDown: the one-tab-page answer", 1)
	}); err != nil {
		return nil, err
	}
	for _, fn := range []string{"ins_pageup", "ins_pagedown"} {
		fn := fn
		if text, err = e.inFunction(text, fn, func(s []byte) ([]byte, error) {
			return e.foldNever(s, `^[ \t]*if \(first_tabpage->tp_next != NULL\)$`,
				fn+": no second tab page to reach")
		}); err != nil {
			return nil, err
		}
	}

	if text, err = e.inFunction(text, "do_window", func(s []byte) ([]byte, error) {
		caseT := regexp.MustCompile(`(?m)^    case 'T':\n`)
		locs := caseT.FindAllIndex(s, -1)
		if len(locs) != 1 {
			return nil, fmt.Errorf("notabs: CTRL-W T is not where this expects")
		}
		m := locs[0]
		end := regexp.MustCompile(`(?m)^    case 't':\n`).FindIndex(s[m[1]:])
		if end == nil {
			return nil, fmt.Errorf("notabs: CTRL-W T is not followed by CTRL-W t")
		}
		block := s[m[0] : m[1]+end[0]]
		if !bytes.Contains(block, []byte("win_new_tabpage")) {
			return nil, fmt.Errorf("notabs: the CTRL-W T block does not open a tab page")
		}
		out := make([]byte, 0, len(s))
		out = append(out, s[:m[0]]...)
		s = append(out, s[m[1]+end[0]:]...)
		fmt.Fprintln(w, "  notabs       CTRL-W T: moving a window to a new tab page")

		var err error
		for _, l := range []struct{ old, new, what string }{
			{`                    case 'f':
                    case 'F':
                        cmdmod.cmod_tab = tabpage_index(curtab) + 1;
                        nchar = xchar;
                        goto wingotofile;
`, `                    case 'f':
                    case 'F':
                        beep_flush();
                        break;
`, "CTRL-W gf and gF: editing a file in a new tab page"},
			// CTRL-W gf was the only goto to it; CTRL-W f falls into the code
			// directly.
			{"wingotofile:\n", "", "the label only CTRL-W gf jumped to"},
			{`                    case 't':
                        goto_tabpage((int)Prenum);
                        break;
`, `                    case 't':
                        if (Prenum > 1)
                        {
                            beep_flush();
                        }
                        break;
`, "CTRL-W gt: the one-tab-page answer"},
			{`                    case 'T':
                        goto_tabpage(-(int)Prenum1);
                        break;
`, `                    case 'T':
                        break;
`, "CTRL-W gT: the one-tab-page answer"},
		} {
			if s, err = e.literal(s, l.old, l.new, l.what, 1); err != nil {
				return nil, err
			}
		}
		return e.foldAlways(s, `^[ \t]*if \(goto_tabpage_lastused\(\) == FAIL\)$`,
			"CTRL-W g<Tab>: beeps")
	}); err != nil {
		return nil, err
	}

	// With no row nothing sets tcl_flags, so it is 0 for ever: "use the
	// last-used tab page" is never asked for, and "go left" never is either.
	if text, err = e.inFunction(text, "alt_tabpage", func(s []byte) ([]byte, error) {
		s, err := e.foldNever(s,
			`^[ \t]*if \(\(tcl_flags & TCL_USELAST\) && valid_tabpage\(lastused_tabpage\)\)$`,
			"alt_tabpage: 'tabclose' asking for the last-used tab page")
		if err != nil {
			return nil, err
		}
		return e.literal(s, `    forward = curtab->tp_next != NULL &&
            ((tcl_flags & TCL_LEFT) == 0 || curtab == first_tabpage);
`, `    forward = curtab->tp_next != NULL;
`, "alt_tabpage: 'tabclose' asking to go left", 1)
	}); err != nil {
		return nil, err
	}

	if text, err = e.literal(text,
		"    (void)opt_strings_flags(p_tcl, p_tcl_values, &tcl_flags, TRUE);\n", "",
		"didset_string_options reading 'tabclose'", 1); err != nil {
		return nil, err
	}

	// Only cmod_tab can be counted here.  goto_tabpage() is still called from
	// ex_tabnext() and ex_tabonly(), whose rows retire pointed away, so the
	// sweep takes those callers; whim36 counts what is left after it.
	// may_open_tabpage() still names it, and has no caller now.
	ga, gz, gone := cutil.FindDefinition(text, cutil.Blank(text), "may_open_tabpage")
	n := 0
	for _, m := range cmodTab.FindAllIndex(text, -1) {
		if gone && ga <= m[0] && m[0] < gz {
			continue
		}
		n++
	}
	if n != 1 {
		return nil, fmt.Errorf("notabs: cmod_tab outside its declaration -- %d mentions, "+
			"expected 1", n)
	}

	e.say("nothing makes or reaches a second tab page")
	return text, nil
}
