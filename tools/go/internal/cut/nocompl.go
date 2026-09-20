package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
	"slimvim.local/tools/internal/dead"
)

// nocomplStubs are the predicates the whole subsystem hangs from, plus the
// popup menu's hooks into the REDRAW loop -- which update_screen() reaches
// rather than completion, so answering pum_visible() is not enough to orphan
// pum_redraw().  pum_display() goes too, so the island behind it is orphaned
// whichever caller survives: chasing them one at a time found three and missed
// two.
var nocomplStubs = []struct{ name, rep string }{
	{"ins_complete", "    return FAIL;"},
	{"ins_compl_prep", "    return FALSE;"},
	{"ins_compl_active", "    return FALSE;"},
	{"pum_visible", "    return FALSE;"},
	{"ins_compl_has_autocomplete", "    return FALSE;"},
	{"pum_redraw_in_same_position", "    return FALSE;"},
	{"pum_may_redraw", ""},
	{"pum_undisplay", ""},
	{"pum_display", ""},
}

// NoCompl removes insert-mode completion and the popup menu.
func NoCompl(text []byte, w io.Writer) ([]byte, error) {
	total := 0
	for _, s := range nocomplStubs {
		blanked := cutil.Blank(text)
		m := regexp.MustCompile(`(?m)^` + regexp.QuoteMeta(s.name) + `\(`).FindIndex(text)
		if m == nil {
			return nil, fmt.Errorf("nocompl: %s is not defined at file scope", s.name)
		}
		o := m[1] + bytes.IndexByte(blanked[m[1]:], '{')
		c := cutil.Match(blanked, o)
		if c < 0 {
			return nil, fmt.Errorf("nocompl: %s is unbalanced", s.name)
		}
		total += bytes.Count(text[o:c], []byte{'\n'})
		var buf []byte
		buf = append(buf, text[:o]...)
		buf = append(buf, "{\n"...)
		if s.rep != "" {
			buf = append(buf, s.rep...)
			buf = append(buf, '\n')
		}
		buf = append(buf, '}')
		text = append(buf, text[c+1:]...)
	}
	fmt.Fprintf(w, "  nocompl      %d lines stubbed in the five predicates the whole "+
		"subsystem hangs from\n", total)

	// One reader the sweep cannot reach, because it is inside edit(): the
	// guard that sends CTRL-N and CTRL-P to `normalchar` when 'complete' is
	// empty.  With the option gone there is nothing to test, and the two keys
	// should take that path unconditionally -- which is what `goto normalchar`
	// already said they should.
	text, err := cutil.DropIf(text,
		`(?m)^[ \t]*if \(\*curbuf->b_p_cpt == NUL && \(ctrl_x_mode_normal\(\) \|\| `+
			`ctrl_x_mode_whole_line\(\)\)`, 1)
	if err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nocompl      edit()'s test for an empty 'complete'")

	// has_compl_option() complains that 'dictionary' or 'thesaurus' is empty.
	// Both options are going, and its two callers are the CTRL-X submode arms
	// for them -- guarded by ctrl_x_mode_thesaurus() and
	// ctrl_x_mode_dictionary(), which can no longer be true.
	n, n2 := 0, 0
	var hit bool
	if text, hit = replaceFirst(regexp.MustCompile(
		`(?m)[ \t]*if \(c == Ctrl_T && ctrl_x_mode_thesaurus\(\)\)\n[ \t]*\{\n`+
			`[ \t]*if \(has_compl_option\(FALSE\)\)\n[ \t]*\{\n`+
			`[ \t]*goto docomplete;\n[ \t]*\}\n[ \t]*break;\n[ \t]*\}\n\n?`), text, ""); hit {
		n = 1
	}
	if text, hit = replaceFirst(regexp.MustCompile(
		`(?m)[ \t]*if \(ctrl_x_mode_dictionary\(\)\)\n[ \t]*\{\n`+
			`[ \t]*if \(has_compl_option\(TRUE\)\)\n[ \t]*\{\n`+
			`[ \t]*goto docomplete;\n[ \t]*\}\n[ \t]*break;\n[ \t]*\}\n`), text, ""); hit {
		n2 = 1
	}
	if n+n2 != 2 {
		return nil, fmt.Errorf("nocompl: the CTRL-X dictionary/thesaurus arms are not "+
			"where this expects (%d, %d)", n, n2)
	}
	var ok bool
	if text, ok = cutil.DeleteDefinition(text, "has_compl_option"); !ok {
		return nil, fmt.Errorf("nocompl: has_compl_option is not defined at file scope")
	}

	// 'infercase' asked smartcase to stand down while completing.
	text = bytes.Replace(text,
		[]byte("if (ic && !no_smartcase && scs && !(ctrl_x_mode_not_default() && curbuf->b_p_inf))"),
		[]byte("if (ic && !no_smartcase && scs)"), 1)

	// `:set autocomplete<` resets a buffer-local boolean to "ask the global".
	// It is the FIRST arm of an else-chain, so removing it has to PROMOTE the
	// next one: dropping the arm and leaving `else if` behind produced a
	// dangling `else` and a function that fell off its end -- which gcc caught
	// as "control reaches end of non-void function", 30 lines away.
	if text, hit = replaceFirst(regexp.MustCompile(
		`(?m)([ \t]*)if \(\(int \*\)varp == &curbuf->b_p_ac && opt_flags == OPT_LOCAL\)\n`+
			`[ \t]*\{\n[ \t]*value = -1;\n[ \t]*\}\n[ \t]*else (if \()`),
		text, "${1}${2}"); !hit {
		return nil, fmt.Errorf("nocompl: `:set autocomplete<` is not where this expects")
	}
	text = regexp.MustCompile(`(?m)^[ \t]*(?:curbuf|buf)->b_p_ac = -1;\n`).ReplaceAll(text, nil)

	// set_shellsize_inner() redraws the popup menu when the terminal resizes --
	// a live path into the pum that completion itself does not reach.
	//
	// SCOPED TO THAT FUNCTION: there are six `if (pum_visible())` in the file
	// and an unanchored cut took the first, which is an arrow-key case in
	// edit().  Harmless there, because the guard is now false either way, but
	// not what was meant -- and the same mistake as `case 't':` and
	// `settmode(TMODE_COOK)` before it.
	blanked := cutil.Blank(text)
	span, found := dead.FuncDefinitions(text, blanked)["set_shellsize_inner"]
	if !found {
		return nil, fmt.Errorf("nocompl: set_shellsize_inner is not defined at file scope")
	}
	fn2, err := cutil.DropIf(text[span[0]:span[1]], `(?m)^[ \t]*if \(pum_visible\(\)\)$`, 1)
	if err != nil {
		return nil, err
	}
	if bytes.Contains(fn2, []byte("ins_compl_show_pum")) {
		return nil, fmt.Errorf("nocompl: set_shellsize_inner's pum block is not the one cut")
	}
	var rebuilt []byte
	rebuilt = append(rebuilt, text[:span[0]]...)
	rebuilt = append(rebuilt, fn2...)
	text = append(rebuilt, text[span[1]:]...)
	fmt.Fprintln(w, "  nocompl      has_compl_option, 'infercase' in smartcase, "+
		"`:set autocomplete<`, and the pum's resize hook")

	// didset_string_options() dereferences every string option's global once
	// at startup.  This is the FOURTH phase to meet it -- 20, 29, 30 and now
	// this one -- and here it was a segfault before the first keystroke,
	// because 'completeopt''s row goes and nothing else reads p_cot.
	if text, err = cutCounted(text,
		`(?m)^[ \t]*\(void\)opt_strings_flags\(p_cot, p_cot_values, &cot_flags, TRUE\);\n`,
		"nocompl", "didset_string_options' p_cot line", 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nocompl      didset_string_options stops reading 'completeopt'")

	return text, nil
}
