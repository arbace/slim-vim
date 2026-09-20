package cut

import (
	"fmt"
	"io"
	"regexp"
)

// noinertoptsEdits are the readers of six globals that are about to lose their
// option rows.
//
// THE THIRD ONE SEGFAULTED.  Every other reader of these six is an ADDRESS
// comparison -- `var == &p_path` -- which survives the global going away
// without noticing.  That one DEREFERENCES p_tc, at startup, in a function
// that runs before anything else, so the editor died before its first
// keystroke and the harness reported it as all 67 behaviour cases, the
// terminal table and every Ex command moving at once.
//
// The address comparisons are harmless at run time -- a test against a
// variable nobody can name is simply false -- but they keep the globals alive,
// and a global that is alive is one the phase's own check cannot prove unread.
var noinertoptsEdits = []struct{ what, pat, repl string }{
	{"ex_drop saving and restoring 'autoread' across nothing",
		`(?m)[ \t]*if \(!bufIsChanged\(curbuf\)\)\n[ \t]*\{\n` +
			`[ \t]*int save_ar = curbuf->b_p_ar;\n\n` +
			`[ \t]*curbuf->b_p_ar = TRUE;\n` +
			`[ \t]*curbuf->b_p_ar = save_ar;\n[ \t]*\}\n`, ""},
	{`` + "`:setlocal autoread` meaning \"follow the global\"",
		`(?m)[ \t]*if \(\(int \*\)varp == &curbuf->b_p_ar && opt_flags == OPT_LOCAL\)\n` +
			`[ \t]*\{\n[ \t]*value = -1;\n[ \t]*\}\n[ \t]*else if`,
		"        if"},
	{"option_expand escaping for 'path' and 'tags'",
		`(?m)[ \t]*int esc = var == &p_tags \|\| var == &p_path;\n`,
		"    int esc = FALSE;\n"},
	// Two sibling blocks, one for directories and one for files, each asking
	// whether the option being completed is one of these three.  Both collapse
	// to the else arm -- and the replacement carries the INDENTATION, because
	// ${1} would keep the inner line's, which is one level too deep once the
	// block around it is gone.
	{"the directory-completion backslash rule for 'path'",
		`(?m)[ \t]*if \(p == \(char_u \*\)&p_path \|\| p == \(char_u \*\)&p_cdpath\)\n` +
			`[ \t]*\{\n[ \t]*xp->xp_backslash = XP_BS_THREE;\n[ \t]*\}\n` +
			`[ \t]*else\n[ \t]*\{\n[ \t]*xp->xp_backslash = XP_BS_ONE;\n[ \t]*\}\n`,
		"            xp->xp_backslash = XP_BS_ONE;\n"},
	// And one term of a longer disjunction, where the other options named are
	// all still real.  Only the term goes.
	{"'path' as a directory-completion context",
		`(?m) \|\| p == \(char_u \*\)&p_path`, ""},
	{"the file-completion backslash rule for 'tags'",
		`(?m)[ \t]*if \(p == \(char_u \*\)&p_tags\)\n` +
			`[ \t]*\{\n[ \t]*xp->xp_backslash = XP_BS_THREE;\n[ \t]*\}\n` +
			`[ \t]*else\n[ \t]*\{\n[ \t]*xp->xp_backslash = XP_BS_ONE;\n[ \t]*\}\n`,
		"            xp->xp_backslash = XP_BS_ONE;\n"},
	{"didset_string_options reading 'tagcase' at startup",
		`(?m)[ \t]*\(void\)opt_strings_flags\(p_tc, p_tc_values, &tc_flags, FALSE\);\n`, ""},
	{"ml_open asking whether this buffer may have a swap file",
		`(?m)[ \t]*if \(p_uc && buf->b_p_swf\)\n[ \t]*\{\n` +
			`[ \t]*buf->b_may_swap = true;\n[ \t]*\}\n` +
			`[ \t]*else\n[ \t]*\{\n[ \t]*buf->b_may_swap = false;\n[ \t]*\}\n`,
		"    buf->b_may_swap = false;\n"},
}

// NoInertOpts removes the last readers of six globals whose option rows go
// with them.
func NoInertOpts(text []byte, w io.Writer) ([]byte, error) {
	for _, e := range noinertoptsEdits {
		re := regexp.MustCompile(e.pat)
		n := len(re.FindAll(text, -1))
		if n != 1 {
			return nil, fmt.Errorf("noinertopts: %s -- expected 1, matched %d", e.what, n)
		}
		text = re.ReplaceAllLiteral(text, []byte(e.repl))
		fmt.Fprintf(w, "  noinertopts  %s\n", e.what)
	}
	return text, nil
}
