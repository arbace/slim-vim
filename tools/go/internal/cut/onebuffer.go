package cut

import (
	"fmt"
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

var (
	bufHideCall = regexp.MustCompile(`\bbuf_hide\(`)
	saveasNew   = "        if (eap->cmdidx == CMD_saveas)\n" +
		"        {\n" +
		"            if (setfname(curbuf, ffname, fname, TRUE) == FAIL)\n" +
		"            {\n" +
		"                goto theend;\n" +
		"            }\n" +
		"            if (*curbuf->b_p_ft == NUL)\n" +
		"            {\n" +
		"                do_modelines(0);\n" +
		"            }\n" +
		"            fname = curbuf->b_sfname;\n" +
		"        }\n"
)

// OneBuffer leaves one buffer: the old one is wiped, nothing is hidden,
// nothing is the alternate.
func OneBuffer(text []byte, w io.Writer) ([]byte, error) {
	e := ed{"onebuffer", w}
	var err error

	text, err = e.inFunction(text, "parse_command_modifiers", func(s []byte) ([]byte, error) {
		s, err := e.subOnce(s,
			`^[ \t]*case 'h':\n[ \t]*if \(p != eap->cmd \|\| !checkforcmd_noparen\(&p, "hide", 3\) \|\| \*p == NUL \|\| ends_excmd\(\*p\)\)\n`+
				`[ \t]*\{\n[ \t]*break;\n[ \t]*\}\n[ \t]*eap->cmd = p;\n`+
				`[ \t]*cmod->cmod_flags \|= CMOD_HIDE;\n[ \t]*continue;\n\n`,
			"the :hide modifier")
		if err != nil {
			return nil, err
		}
		return e.dropIf(s, `^[ \t]*if \(checkforcmd_noparen\(&eap->cmd, "keepalt", 5\)\)$`,
			"the :keepalt modifier")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "set_context_by_cmdname", func(s []byte) ([]byte, error) {
		return e.subCount(s, `^[ \t]*case CMD_(?:hide|keepalt):\n`,
			"completion for :hide and :keepalt", 2)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "do_argfile", func(s []byte) ([]byte, error) {
		s, err := e.foldNever(s, `^[ \t]*if \(buf_hide\(curbuf\)\)$`,
			"do_argfile asking whether the file is another")
		if err != nil {
			return nil, err
		}
		for _, l := range []struct{ old, new, what string }{
			{"(!buf_hide(curbuf) || !other) && ", "", "do_argfile checking a hidden buffer"},
			{"(other ? 0 : CCGD_MULTWIN) | ", "", "do_argfile checking the same file in two windows"},
		} {
			if s, err = e.literal(s, l.old, l.new, l.what, 1); err != nil {
				return nil, err
			}
		}
		if s, err = e.subOnce(s, `^[ \t]*other = TRUE;\n`,
			"do_argfile assuming another file"); err != nil {
			return nil, err
		}
		return e.literal(s, "(buf_hide(curwin->w_buffer) ? ECMD_HIDE : 0) + ", "",
			"do_argfile hiding the buffer", 1)
	})
	if err != nil {
		return nil, err
	}

	// THE ORDER IS THE PYTHON'S.  These four one-line edits invite a loop --
	// they are the same shape in four different functions -- but the Python
	// interleaves them with getfile's pair and ex_quit's pair, and each edit
	// prints as it succeeds.  Looping them emitted the same lines in a
	// different order and 7 inputs differed.
	for _, f := range []struct{ fn, old, new, what string }{
		{"ex_next", "(       buf_hide(curbuf) || ", "(", ":next hiding the buffer"},
		{"set_curbuf", "!buf_hide(prevbuf) && ", "", "set_curbuf hiding the buffer"},
	} {
		f := f
		if text, err = e.inFunction(text, f.fn, func(s []byte) ([]byte, error) {
			return e.literal(s, f.old, f.new, f.what, 1)
		}); err != nil {
			return nil, err
		}
	}

	text, err = e.inFunction(text, "getfile", func(s []byte) ([]byte, error) {
		s, err := e.literal(s, " && !buf_hide(curbuf) && ", " && ",
			"getfile writing before it leaves", 1)
		if err != nil {
			return nil, err
		}
		return e.literal(s, "(buf_hide(curbuf) ? ECMD_HIDE : 0) + ", "",
			"getfile hiding the buffer", 1)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "can_abandon", func(s []byte) ([]byte, error) {
		return e.literal(s, "(       buf_hide(buf) || ", "(", "can_abandon a hidden buffer", 1)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "ex_quit", func(s []byte) ([]byte, error) {
		s, err := e.literal(s, "(!buf_hide(wp->w_buffer) && check_changed(", "(check_changed(",
			":quit sparing a hidden buffer", 1)
		if err != nil {
			return nil, err
		}
		return e.literal(s, "win_close(wp, !buf_hide(wp->w_buffer) || eap->forceit)",
			"win_close(wp, TRUE)", ":quit freeing the buffer", 1)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "ex_exit", func(s []byte) ([]byte, error) {
		return e.literal(s, "win_close(curwin, !buf_hide(curwin->w_buffer))",
			"win_close(curwin, TRUE)", ":exit freeing the buffer", 1)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "do_exedit", func(s []byte) ([]byte, error) {
		for _, l := range []struct{ old, new, what string }{
			{"(buf_hide(curbuf) ? ECMD_HIDE : 0) + ", "", ":edit hiding the buffer"},
			{"if (!need_hide || buf_hide(curbuf))", "if (!need_hide)",
				":edit closing a failed window"},
			{"!need_hide && !buf_hide(curbuf)", "!need_hide", ":edit freeing a failed window"},
		} {
			var err error
			if s, err = e.literal(s, l.old, l.new, l.what, 1); err != nil {
				return nil, err
			}
		}
		return e.dropIf(s,
			`^[ \t]*if \(old_curwin != NULL && \*eap->arg != NUL && curwin != old_curwin && win_valid\(old_curwin\) && `+
				`old_curwin->w_buffer != curbuf && \(cmdmod\.cmod_flags & CMOD_KEEPALT\) == 0\)$`,
			":edit leaving an alternate in the old window")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "nv_gotofile", func(s []byte) ([]byte, error) {
		s, err := e.literal(s, " && !buf_hide(curbuf))", ")", "gf refusing a changed buffer", 1)
		if err != nil {
			return nil, err
		}
		return e.literal(s, "buf_hide(curbuf) ? ECMD_HIDE : 0", "0", "gf hiding the buffer", 1)
	})
	if err != nil {
		return nil, err
	}
	if n := len(bufHideCall.FindAll(text, -1)); n != 2 {
		return nil, fmt.Errorf("onebuffer: buf_hide is still called -- %d mentions, expected "+
			"its prototype and definition", n)
	}

	text, err = e.inFunction(text, "close_buffer", func(s []byte) ([]byte, error) {
		var err error
		for _, b := range []struct{ ch, what string }{
			{"d", "delete"}, {"w", "wipe"}, {"u", "unload"},
		} {
			if s, err = e.foldNever(s, `^[ \t]*if \(buf->b_p_bh\[0\] == '`+b.ch+`'\)$`,
				"close_buffer's bufhidden="+b.what); err != nil {
				return nil, err
			}
		}
		return s, nil
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "do_ecmd", func(s []byte) ([]byte, error) {
		s, err := e.literal(s, "(flags & ECMD_HIDE) ? 0 : DOBUF_UNLOAD", "DOBUF_WIPE",
			"do_ecmd wiping the buffer it leaves", 1)
		if err != nil {
			return nil, err
		}
		if s, err = e.dropIf(s, `^[ \t]*if \(fnum == 0 && other_file && ffname != NULL\)$`,
			"do_ecmd naming a refused file the alternate"); err != nil {
			return nil, err
		}
		if s, err = e.literal(s, "        int prev_alt_fnum = curwin->w_alt_fnum;\n\n", "",
			"do_ecmd remembering the alternate", 1); err != nil {
			return nil, err
		}
		if s, err = e.dropIf(s, `^[ \t]*if \(\(cmdmod\.cmod_flags & CMOD_KEEPALT\) == 0\)$`,
			"do_ecmd making the old buffer the alternate"); err != nil {
			return nil, err
		}
		if s, err = e.subOnce(s,
			`^[ \t]*if \(oldwin != NULL\)\n[ \t]*\{\n[ \t]*buflist_altfpos\(oldwin\);\n[ \t]*\}\n`,
			"do_ecmd saving the old window position"); err != nil {
			return nil, err
		}
		return e.dropIf(s,
			`^[ \t]*if \(curwin->w_alt_fnum == buf->b_fnum && prev_alt_fnum != 0\)$`,
			"do_ecmd restoring the alternate")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "set_curbuf", func(s []byte) ([]byte, error) {
		s, err := e.dropIf(s, `^[ \t]*if \(\(cmdmod\.cmod_flags & CMOD_KEEPALT\) == 0\)$`,
			"set_curbuf making the old buffer the alternate")
		if err != nil {
			return nil, err
		}
		return e.subOnce(s, `^[ \t]*buflist_altfpos\(curwin\);\n`,
			"set_curbuf saving the window position")
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "rename_buffer", func(s []byte) ([]byte, error) {
		s, err := e.dropIf(s, `^[ \t]*if \(xfname != NULL && \*xfname != NUL\)$`,
			":file keeping the old name as the alternate")
		if err != nil {
			return nil, err
		}
		// xfname held the old short name for that alternate alone.
		if s, err = e.literal(s, "    char_u *xfname;\n", "",
			":file declaring the old short name", 1); err != nil {
			return nil, err
		}
		return e.literal(s, "    xfname = curbuf->b_fname;\n", "",
			":file saving the old short name", 1)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "win_init", func(s []byte) ([]byte, error) {
		return e.literal(s, "    newp->w_alt_fnum = oldp->w_alt_fnum;\n", "",
			"win_init copying the alternate", 1)
	})
	if err != nil {
		return nil, err
	}
	text, err = e.inFunction(text, "ex_read", func(s []byte) ([]byte, error) {
		return e.dropIf(s, `^[ \t]*if \(vim_strchr\(p_cpo, CPO_ALTREAD\) != NULL\)$`,
			":read naming the alternate")
	})
	if err != nil {
		return nil, err
	}
	text, err = e.inFunction(text, "buflist_findnr", func(s []byte) ([]byte, error) {
		return e.dropIf(s, `^[ \t]*if \(nr == 0\)$`, "buffer 0 meaning the alternate")
	})
	if err != nil {
		return nil, err
	}
	text, err = e.inFunction(text, "buflist_findpat", func(s []byte) ([]byte, error) {
		return e.literal(s, "match = curwin->w_alt_fnum;", "match = 0;",
			"'#' finding the alternate", 1)
	})
	if err != nil {
		return nil, err
	}

	// A ROW IS NEVER DELETED FROM nv_cmds[], IT IS POINTED AT nv_error.
	if text, err = e.subCountRepl(text,
		`(?m)^([ \t]*\{Ctrl_HAT, )nv_hat(, NV_NCW, 0\} ,)$`, "${1}nv_error${2}",
		"CTRL-^'s row points at nv_error", 1); err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "do_write", func(s []byte) ([]byte, error) {
		s, err := e.dropIf(s, `^    if \(other\)$`,
			":write making the written name the alternate")
		if err != nil {
			return nil, err
		}
		return e.subCountRepl(s,
			`(?ms)^        if \(eap->cmdidx == CMD_saveas && alt_buf != NULL\)\n        \{\n.*?\n`+
				`            fname = curbuf->b_sfname;\n        \}\n`,
			saveasNew,
			":saveas renaming the one buffer instead of swapping names with another", 1)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "alist_add", func(s []byte) ([]byte, error) {
		return e.subCountRepl(s,
			`(?m)^([ \t]*)if \(set_fnum > 0\)\n[ \t]*\{\n([ \t]*\(\(aentry_T \*\)\(\(al\)->al_ga\.ga_data\)\) \[al->al_ga\.ga_len\]\.ae_fnum =)\n`+
				`[ \t]*buflist_add\(fname, BLN_LISTED \| \(set_fnum == 2 \? BLN_CURBUF : 0\)\);\n[ \t]*\}\n`,
			"${2} 0;\n${1}if (set_fnum == 2 && curbuf_reusable())\n${1}{\n${2}\n${1}        buflist_add(fname, BLN_LISTED | BLN_CURBUF);\n${1}}\n",
			"an argument naming a buffer only when it is the empty startup one", 1)
	})
	if err != nil {
		return nil, err
	}

	text, err = e.inFunction(text, "alist_add_list", func(s []byte) ([]byte, error) {
		s, err := e.subOnce(s,
			`(?m)^[ \t]*int flags = BLN_LISTED \| \(will_edit \? BLN_CURBUF : 0\);\n\n`,
			"alist_add_list choosing buffer flags")
		if err != nil {
			return nil, err
		}
		return e.literal(s, ".ae_fnum = buflist_add(files[i], flags);", ".ae_fnum = 0;",
			"alist_add_list making a buffer per argument", 1)
	})
	if err != nil {
		return nil, err
	}

	// setaltfname() and buf_hide() have no caller now and still name the
	// alternate and the two modifier flags; the sweep takes them, and whim42
	// counts again after it.  Everything else is counted here.
	blanked := cutil.Blank(text)
	var dying [][2]int
	for _, n := range []string{"setaltfname", "buf_hide"} {
		if a, z, ok := cutil.FindDefinition(text, blanked, n); ok {
			dying = append(dying, [2]int{a, z})
		}
	}
	count := func(pattern string) int {
		n := 0
		for _, m := range regexp.MustCompile(pattern).FindAllIndex(text, -1) {
			in := false
			for _, sp := range dying {
				if sp[0] <= m[0] && m[0] < sp[1] {
					in = true
					break
				}
			}
			if !in {
				n++
			}
		}
		return n
	}
	var left []string
	for _, c := range []struct {
		what, pattern string
		want          int
	}{
		{"w_alt_fnum outside its field", `\bw_alt_fnum\b`, 1},
		{"CMOD_KEEPALT or CMOD_HIDE outside their enumerators", `\bCMOD_(?:KEEPALT|HIDE)\b`, 2},
		{"buflist_altfpos called", `\bbuflist_altfpos\(curwin\)|\bbuflist_altfpos\(oldwin\)`, 0},
		{"nv_hat in the key table", `\{Ctrl_HAT, nv_hat`, 0},
	} {
		if n := count(c.pattern); n != c.want {
			left = append(left, fmt.Sprintf("(%s, %d)", cutil.PyRepr(c.what), n))
		}
	}
	if len(left) > 0 {
		return nil, fmt.Errorf("onebuffer: still present: [%s]", strings.Join(left, ", "))
	}

	e.say("one buffer: the old one is wiped, nothing is hidden, nothing is the alternate")
	return text, nil
}
