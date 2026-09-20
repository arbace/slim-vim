package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// complkeysStubs are predicates the rest of the editor asks on its own
// account.  Each already had only one honest answer; saying it in the body is
// what lets the sweep reach everything behind it.
var complkeysStubs = []struct{ name, ret string }{
	{"ins_compl_win_active", "    return FALSE;"},
	{"ins_compl_lnum_in_range", "    return FALSE;"},
	{"ins_compl_col_range_attr", "    return -1;"},
	{"ins_compl_preinsert_effect", "    return FALSE;"},
	{"ins_compl_autocomplete_pending", "    return FALSE;"},
	{"ins_compl_autocomplete_elapsed", "    return 0;"},
	{"pum_under_menu", "    return FALSE;"},
	{"pum_get_height", "    return 0;"},
	{"vim_is_ctrl_x_key", "    return FALSE;"},
	// With ins_ctrl_x() empty, `ctrl_x_mode` is never assigned and stays
	// CTRL_X_NORMAL, so these two are decided.  ins_ctrl_ey() then takes its
	// else branch, which is CTRL-Y and CTRL-E's ordinary meaning.
	{"ctrl_x_mode_scroll", "    return FALSE;"},
	{"at_ins_compl_key", "    return FALSE;"},
}

// complkeysStub replaces a definition's body with a constant answer.
//
// TWO SHAPES, and only looking for one of them cost this phase a pass.  Most
// definitions here put the return type on its own line and the name at column
// zero, so `^name\(` finds them.  The ctrl_x_mode_*() predicates are one-liners
// -- `static int ctrl_x_mode_scroll(void)` with the body on the next line --
// and the anchored search does not see them at all.
//
// So find the name, and LET THE C DECIDE: a definition is the occurrence whose
// matching `)` is followed by `{`.  A prototype ends in `;` and is skipped.
func complkeysStub(text []byte, name, ret string) ([]byte, error) {
	blanked := cutil.Blank(text)
	re := regexp.MustCompile(`\b` + regexp.QuoteMeta(name) + `\s*\(`)
	pos := 0
	for {
		m := re.FindIndex(blanked[pos:])
		if m == nil {
			return nil, fmt.Errorf("nocomplkeys: %s is not defined", name)
		}
		lp := pos + m[1] - 1
		rp := cutil.Match(blanked, lp)
		if rp < 0 {
			return nil, fmt.Errorf("nocomplkeys: %s has an unbalanced argument list", name)
		}
		hi := rp + 40
		if hi > len(blanked) {
			hi = len(blanked)
		}
		rest := bytes.TrimLeft(blanked[rp+1:hi], " \t\n\r\v\f")
		pos = rp + 1
		if len(rest) > 0 && rest[0] == '{' {
			o := rp + bytes.IndexByte(blanked[rp:], '{')
			c := cutil.Match(blanked, o)
			if c < 0 {
				return nil, fmt.Errorf("nocomplkeys: %s is unbalanced", name)
			}
			out := make([]byte, 0, len(text))
			out = append(out, text[:o]...)
			out = append(out, "{\n"...)
			if ret != "" {
				out = append(out, ret...)
				out = append(out, '\n')
			}
			out = append(out, '}')
			return append(out, text[c+1:]...), nil
		}
	}
}

// complkeysDropUnique is DropIf, but only when the condition occurs exactly
// once.
//
// The first version of this phase dropped
// `if (c != KE_CURSORHOLD && c != KE_COMPLETE_DELAY)` by pattern.  That
// condition appears three times inside edit(), and the one it took was
// `{ lastc = c; }` -- the last-character save, which has nothing to do with
// completion.  It compiled, it swept clean, and the island still shrank by
// 2,400 lines, so nothing downstream objected.
//
// A CUT THAT IS NOT UNIQUE IS NOT A CUT, IT IS A GUESS.
func complkeysDropUnique(text []byte, cond, what string) ([]byte, error) {
	n := bytes.Count(text, []byte(cond))
	if n != 1 {
		return nil, fmt.Errorf("nocomplkeys: %s -- the condition occurs %d times, not once",
			what, n)
	}
	return cutil.DropIf(text, `(?m)^[ \t]*`+regexp.QuoteMeta(cond), 1)
}

// complkeysDropIn is DropIf restricted to one function.
//
// The pattern that names do_put's cleanup also matches four copies inside the
// completion code itself, and a bare search takes the first.  That edits the
// island instead of the caller keeping it alive -- and the island then does
// not die, because the reachable call is still there.
func complkeysDropIn(text []byte, fn, pattern, what string) ([]byte, error) {
	a, z, ok := cutil.FindDefinition(text, cutil.Blank(text), fn)
	if !ok {
		return nil, fmt.Errorf("nocomplkeys: %s is not defined", fn)
	}
	inner, err := cutil.DropIf(text[a:z], pattern, 1)
	if err != nil {
		return nil, err
	}
	if bytes.Equal(inner, text[a:z]) {
		return nil, fmt.Errorf("nocomplkeys: %s -- nothing dropped in %s", what, fn)
	}
	out := make([]byte, 0, len(text))
	out = append(out, text[:a]...)
	out = append(out, inner...)
	return append(out, text[z:]...), nil
}

func complkeysSub(text []byte, old, new, what string, count int) ([]byte, error) {
	n := bytes.Count(text, []byte(old))
	if n != count {
		return nil, fmt.Errorf("nocomplkeys: %s -- expected %d, found %d", what, count, n)
	}
	return bytes.Replace(text, []byte(old), []byte(new), count), nil
}

const complkeysDisarm = `        if (c !=   (-((KS_EXTRA) + ((int)(KE_CURSORHOLD) << 8)))   && c !=   (-((KS_EXTRA) + ((int)(KE_COMPLETE_DELAY) << 8)))  )
        {
            ins_compl_clear_autocomplete_delay();
            ins_compl_disarm_autostart();
            if (!ins_compl_active())
            {
                ins_compl_disable_autocomplete();
            }
        }

`

const complkeysDelayArm = `            ins_compl_clear_autocomplete_delay();
            if (!ins_compl_has_autocomplete() || char_avail() || curwin->w_cursor.col == 0)
            {
                break;
            }
            c = char_before_cursor();
            if (!vim_isprintc(c))
            {
                break;
            }
            ins_compl_enable_autocomplete();
            ins_compl_arm_autostart();
            goto docomplete;
`

const complkeysDoCompleteOld = `            if (!ctrl_x_mode_whole_line())
            {
                if (p_im)
                {
                    if (echeck_abbr(Ctrl_L + ABBR_OFF))
                    {
                        break;
                    }
                    goto doESCkey;
                }
                goto normalchar;
            }

        __attribute__((fallthrough));
        case Ctrl_P:
        case Ctrl_N:
docomplete:
            ins_compl_clear_autocomplete_delay();
            compl_busy = TRUE;
            if (ins_complete(c, TRUE) == FAIL)
            {
                compl_status_clear();
            }
            compl_busy = FALSE;
            can_si = may_do_si();
            break;
`

const complkeysDoCompleteNew = `            if (p_im)
            {
                if (echeck_abbr(Ctrl_L + ABBR_OFF))
                {
                    break;
                }
                goto doESCkey;
            }
            goto normalchar;

        case Ctrl_P:
        case Ctrl_N:
            break;
`

var (
	complkeysBlob = regexp.MustCompile(
		`(?m)[ \t]*if \(did_backspace\)\n[ \t]*\{\n` +
			`[ \t]*if \(ins_compl_has_autocomplete\(\)[^\n]*\n[ \t]*\{[^\n]*\n` +
			`[ \t]*\}\n`)
	complkeysPumArm = regexp.MustCompile(
		`[ \t]*if \(pum_visible\(\)\)\n[ \t]*\{\n[ \t]*goto docomplete;\n[ \t]*\}\n\n?`)
)

// NoComplKeys takes the completion keys away.
func NoComplKeys(text []byte, w io.Writer) ([]byte, error) {
	text, err := complkeysStub(text, "ins_ctrl_x", "")
	if err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  complkeys    CTRL-X opens no submode; ctrl_x_mode stays normal")

	for _, s := range []struct{ old, new, what string }{
		{"    if (textlock != 0 || ins_compl_active() || compl_busy || pum_visible())",
			"    if (textlock != 0)", "edit()'s entry guard"},
		{"    ins_compl_clear();\n", "", "edit()'s ins_compl_clear"},
		{"        if (stop_insert_mode && !ins_compl_active())",
			"        if (stop_insert_mode)", "the stop_insert_mode guard"},
	} {
		if text, err = complkeysSub(text, s.old, s.new, s.what, 1); err != nil {
			return nil, err
		}
	}

	if text, err = complkeysDropUnique(text,
		"if (ins_compl_has_autocomplete() && !char_avail() && curwin->w_cursor.col > 0)",
		"the ins_just_started autocomplete arm"); err != nil {
		return nil, err
	}
	if text, err = complkeysSub(text, "                    ins_compl_prep(ESC);\n", "",
		"the ESC hook", 1); err != nil {
		return nil, err
	}
	if text, err = complkeysSub(text, complkeysDisarm, "",
		"the per-key autocomplete disarm", 1); err != nil {
		return nil, err
	}
	if text, err = complkeysDropUnique(text,
		"if (ins_compl_active() && curwin->w_cursor.col >= ins_compl_col() && ins_compl_has_shown_match() && pum_wanted())",
		"a completion arm"); err != nil {
		return nil, err
	}
	if text, err = complkeysSub(text, "        ins_compl_init_get_longest();\n", "",
		"edit()'s init_get_longest", 1); err != nil {
		return nil, err
	}
	for _, d := range []struct{ cond, what string }{
		{"if (ins_compl_prep(c))", "the per-key prep hook"},
		{"if ((c == Ctrl_V || c == Ctrl_Q) && ctrl_x_mode_cmdline())",
			"CTRL-V in cmdline completion"},
	} {
		if text, err = complkeysDropUnique(text, d.cond, d.what); err != nil {
			return nil, err
		}
	}
	if text, err = complkeysSub(text,
		"doESCkey:\n            ins_compl_clear_autocomplete_delay();\n",
		"doESCkey:\n", "the doESCkey disarm", 1); err != nil {
		return nil, err
	}
	if text, err = complkeysDropUnique(text,
		"if (ctrl_x_mode_register() && !ins_compl_active())", "a completion arm"); err != nil {
		return nil, err
	}

	// The three one-line blobs macro expansion left behind, each inside an
	// `if (did_backspace)` that is then empty.
	n := len(complkeysBlob.FindAll(text, -1))
	if n != 3 {
		return nil, fmt.Errorf("nocomplkeys: the backspace autocomplete blobs -- "+
			"expected 3, matched %d", n)
	}
	text = complkeysBlob.ReplaceAll(text, nil)
	fmt.Fprintf(w, "  complkeys    autocomplete disarmed at %d sites\n", n+3)

	if text, err = complkeysSub(text, complkeysDelayArm, "            break;\n",
		"the KE_COMPLETE_DELAY arm", 1); err != nil {
		return nil, err
	}

	if n = len(complkeysPumArm.FindAll(text, -1)); n != 4 {
		return nil, fmt.Errorf("nocomplkeys: the arrow-key pum arms -- expected 4, matched %d", n)
	}
	text = complkeysPumArm.ReplaceAll(text, nil)
	fmt.Fprintln(w, "  complkeys    Up, Down, PageUp and PageDown no longer move a selection")

	for _, k := range []struct{ key, mode string }{
		{"Ctrl_RSB", "ctrl_x_mode_tags"},
		{"Ctrl_F", "ctrl_x_mode_files"},
		{"Ctrl_S", "ctrl_x_mode_spell"},
	} {
		old := "            if (!" + k.mode + "())\n" +
			"            {\n" +
			"                goto normalchar;\n" +
			"            }\n" +
			"            goto docomplete;\n"
		if text, err = complkeysSub(text, old, "            goto normalchar;\n",
			"the "+k.key+" arm", 1); err != nil {
			return nil, err
		}
	}

	if text, err = complkeysSub(text, complkeysDoCompleteOld, complkeysDoCompleteNew,
		"the docomplete label", 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  complkeys    docomplete is gone; CTRL-N and CTRL-P do nothing")

	for _, d := range []struct{ cond, what string }{
		{"if (ins_compl_has_autocomplete() && !char_avail() && vim_isprintc(c))",
			"the printable-character autocomplete arm"},
		{"if (ins_compl_active() && !ins_compl_win_active(curwin))",
			"the end-of-loop cancel"},
	} {
		if text, err = complkeysDropUnique(text, d.cond, d.what); err != nil {
			return nil, err
		}
	}

	if text, err = complkeysDropIn(text, "do_put",
		`(?m)^[ \t]*`+regexp.QuoteMeta("if (ins_compl_preinsert_effect())"),
		"do_put's preinsert cleanup"); err != nil {
		return nil, err
	}

	for _, s := range complkeysStubs {
		if text, err = complkeysStub(text, s.name, s.ret); err != nil {
			return nil, err
		}
	}
	fmt.Fprintf(w, "  complkeys    %d predicates answer without the machinery\n",
		len(complkeysStubs))

	return text, nil
}
