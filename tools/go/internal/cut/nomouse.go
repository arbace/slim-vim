package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

// ke is a `case (-((KS_EXTRA) + ((int)(NAME) << 8))) :` label, as the macro
// expander leaves it.
func ke(name string) string {
	return `[ \t]*case   \(-\(\(KS_EXTRA\) \+ \(\(int\)\(` + name + `\) << 8\)\)\)  :\n`
}

var insMouseKeys = []string{
	"KE_LEFTMOUSE", "KE_LEFTMOUSE_NM", "KE_LEFTDRAG", "KE_LEFTRELEASE",
	"KE_LEFTRELEASE_NM", "KE_MOUSEMOVE", "KE_MIDDLEMOUSE",
	"KE_MIDDLEDRAG", "KE_MIDDLERELEASE", "KE_RIGHTMOUSE",
	"KE_RIGHTDRAG", "KE_RIGHTRELEASE", "KE_X1MOUSE", "KE_X1DRAG",
	"KE_X1RELEASE", "KE_X2MOUSE", "KE_X2DRAG", "KE_X2RELEASE",
}

const mouseKeyNames = `LeftDrag|LeftMouse|LeftRelease|LeftReleaseNM|MiddleMouse|` +
	`MouseMove|RightMouse|ScrollWheelDown|ScrollWheelLeft|` +
	`ScrollWheelRight|ScrollWheelUp|X1Mouse|X2Mouse|Mouse`

var (
	mouseRow      = regexp.MustCompile(`(?m)^([ \t]*\{[^\n]*, )nv_mouse(?:scroll)?(, [^\n]*\} ,)$`)
	mchSetmouse   = regexp.MustCompile(`(?m)^[ \t]*mch_setmouse\((?:TRUE|FALSE)\);\n`)
	mchSetmouseW  = regexp.MustCompile(`\bmch_setmouse\b`)
	setmouseCall  = regexp.MustCompile(`(?m)^[ \t]*setmouse\(\);\n`)
	anyMouse      = regexp.MustCompile(`(?i)mouse`)
	insScrollCase = regexp.MustCompile(
		`(?m)[ \t]*case   \(-\(\(KS_EXTRA\) \+ \(\(int\)\(KE_MOUSE(?:DOWN|UP|LEFT|RIGHT)\) << 8\)\)\)  :\n` +
			`[ \t]*ins_mousescroll\([^;]*\);\n[ \t]*break;\n\n?`)
)

// NoMouse removes the mouse.
func NoMouse(text []byte, w io.Writer) ([]byte, error) {
	// POINTED AT nv_error, NEVER DELETED.  nv_cmd_idx[] is a sorted index into
	// nv_cmds[], computed once and written into the C; deleting these rows
	// left it 22 entries longer than the table, and every key found past the
	// first hole -- the arrows among them -- resolved to the wrong row.
	n := len(mouseRow.FindAll(text, -1))
	if n != 22 {
		return nil, fmt.Errorf("nomouse: expected 22 nv_cmds mouse rows, matched %d", n)
	}
	text = mouseRow.ReplaceAll(text, []byte("${1}nv_error${2}"))
	fmt.Fprintf(w, "  nomouse      %d rows of nv_cmds answer nv_error\n", n)

	keyRows := regexp.MustCompile(
		`(?m)^[ \t]*\{TRUE,[^\n]*\{\(char_u \*\)\("(?:` + mouseKeyNames + `)"\),[^\n]*\},\n`)
	n = len(keyRows.FindAll(text, -1))
	if n != 14 {
		return nil, fmt.Errorf("nomouse: expected 14 key-name rows, matched %d", n)
	}
	text = keyRows.ReplaceAll(text, nil)
	fmt.Fprintf(w, "  nomouse      %d rows of the key-name table\n", n)

	var err error
	var insCases strings.Builder
	for _, k := range insMouseKeys {
		insCases.WriteString(ke(k))
	}
	if text, err = cutCounted(text,
		"(?m)"+insCases.String()+`[ \t]*ins_mouse\(c\);\n[ \t]*break;\n\n?`,
		"nomouse", "edit()'s mouse cases", 1); err != nil {
		return nil, err
	}
	if n = len(insScrollCase.FindAll(text, -1)); n != 4 {
		return nil, fmt.Errorf("nomouse: expected 4 ins_mousescroll cases, matched %d", n)
	}
	text = insScrollCase.ReplaceAll(text, nil)
	fmt.Fprintln(w, "  nomouse      edit()'s mouse and scroll cases")

	for _, c := range []struct{ pat, what string }{
		{ke("KE_MIDDLEDRAG") + ke("KE_MIDDLERELEASE") +
			`[ \t]*goto cmdline_not_changed;\n\n?`,
			"getcmdline_int()'s middle drag and release"},
		{ke("KE_MIDDLEMOUSE") +
			`[ \t]*if \(!mouse_has\(MOUSE_COMMAND\)\)\n[ \t]*\{\n` +
			`[ \t]*goto cmdline_not_changed;\n[ \t]*\}\n` +
			`[ \t]*cmdline_paste\(0, TRUE, TRUE\);\n` +
			`[ \t]*redrawcmd\(\);\n[ \t]*goto cmdline_changed;\n\n?`,
			"getcmdline_int()'s middle-click paste"},
		{ke("KE_LEFTDRAG") + ke("KE_LEFTRELEASE") +
			ke("KE_RIGHTDRAG") + ke("KE_RIGHTRELEASE") +
			`[ \t]*if \(ignore_drag_release\)\n[ \t]*\{\n` +
			`[ \t]*goto cmdline_not_changed;\n[ \t]*\}\n` +
			`[ \t]*__attribute__\(\(fallthrough\)\);\n` +
			ke("KE_LEFTMOUSE") + ke("KE_RIGHTMOUSE") +
			`[ \t]*cmdline_left_right_mouse\(c, &ignore_drag_release\);\n` +
			`[ \t]*goto cmdline_not_changed;\n\n?`,
			"getcmdline_int()'s click and drag"},
		{ke("KE_MOUSEDOWN") + ke("KE_MOUSEUP") + ke("KE_MOUSELEFT") +
			ke("KE_MOUSERIGHT") + `[ \t]*goto cmdline_not_changed;\n\n?`,
			"getcmdline_int()'s scroll cases"},
		{ke("KE_X1MOUSE") + ke("KE_X1DRAG") + ke("KE_X1RELEASE") +
			ke("KE_X2MOUSE") + ke("KE_X2DRAG") + ke("KE_X2RELEASE") +
			ke("KE_MOUSEMOVE") + `[ \t]*goto cmdline_not_changed;\n\n?`,
			"getcmdline_int()'s side-button cases"},
		{`^[ \t]*int[ \t]+ignore_drag_release = TRUE;\n`, "ignore_drag_release"},
		{`^[ \t]*ignore_drag_release = TRUE;\n`, "ignore_drag_release's other assignment"},
	} {
		if text, err = cutCounted(text, "(?m)"+c.pat, "nomouse", c.what, 1); err != nil {
			return nil, err
		}
	}
	fmt.Fprintln(w, "  nomouse      getcmdline_int()'s six mouse case runs")

	for _, c := range []struct{ pat, what string }{
		{`[ \t]*\(void\)do_mouse\(cap->oap, cap->nchar, \(cap->cmdchar == '\]'\) \? FORWARD :  \(-1\) , cap->count1, PUT_FIXINDENT\);\n`,
			"nv_brackets()'s ]<LeftMouse>"},
		{`[ \t]*\(void\)do_mouse\(oap, cap->nchar,  \(-1\) , cap->count1, 0\);\n`,
			"nv_g_cmd()'s g<LeftMouse>"},
	} {
		if text, err = cutCounted(text, "(?m)"+c.pat, "nomouse", c.what, 1); err != nil {
			return nil, err
		}
	}
	fmt.Fprintln(w, "  nomouse      ]<LeftMouse> and g<LeftMouse>")

	if text, err = cutCounted(text,
		`(?m)[ \t]*\(void\)jump_to_mouse\(MOUSE_SETPOS, NULL, 0\);\n`,
		"nomouse", "wait_return()'s jump_to_mouse", 1); err != nil {
		return nil, err
	}
	// No (?m): the Python passes flags=0 for this one.
	if text, err = cutCounted(text,
		` \|\| \(!mouse_has\(MOUSE_RETURN\) && mouse_row < msg_row && `+
			`\(c ==[^;]*KE_X2MOUSE\) << 8\)\)\)  \)\)`,
		"nomouse", "wait_return()'s mouse_has term", 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nomouse      the click that dismissed a `Press ENTER` prompt")

	if text, err = cutil.DropIf(text,
		`(?m)^[ \t]*if \(check_termcode_mouse\(tp, &slen, key_name, modifiers_start, idx, &modifiers\) == -1\)$`,
		1); err != nil {
		return nil, err
	}

	// set_termname() decides which mouse protocol the terminal speaks --
	// reading the 1006 capability, setting 'ttymouse' from it, and installing
	// the termcodes.  Forty lines, from `did_set_ttym` to the end of the block
	// that calls check_mouse_termcode().
	blanked := cutil.Blank(text)
	k := bytes.Index(text, []byte("    int did_set_ttym = FALSE;\n"))
	if k < 0 {
		return nil, fmt.Errorf("nomouse: set_termname()'s mouse block is not where this expects")
	}
	pAt := k + bytes.Index(text[k:], []byte(`char_u  *p = (char_u *)"";`)) - 40
	o := pAt + bytes.IndexByte(blanked[pAt:], '{')
	c := cutil.Match(blanked, o)
	if c < 0 {
		return nil, fmt.Errorf("nomouse: set_termname()'s mouse block is unbalanced")
	}
	end := c + bytes.IndexByte(text[c:], '\n') + 1
	if end < len(text) && text[end] == '\n' {
		end++
	}
	if !bytes.Contains(text[k:end], []byte("check_mouse_termcode")) {
		return nil, fmt.Errorf("nomouse: set_termname()'s mouse block is not where this expects")
	}
	fmt.Fprintf(w, "  nomouse      set_termname()'s %d lines of protocol negotiation\n",
		bytes.Count(text[k:end], []byte{'\n'}))
	var buf []byte
	buf = append(buf, text[:k]...)
	text = append(buf, text[end:]...)
	fmt.Fprintln(w, "  nomouse      the escape sequences that carried a click")

	if n = len(setmouseCall.FindAll(text, -1)); n != 31 {
		return nil, fmt.Errorf("nomouse: expected 31 setmouse() calls, matched %d", n)
	}
	text = setmouseCall.ReplaceAll(text, nil)
	// Every mch_setmouse() call is a bare statement too.  The count is NOT
	// hardcoded: what is asserted is that afterwards only the definition and
	// its forward declaration are left, which the sweep then takes.
	text = mchSetmouse.ReplaceAll(text, nil)
	if left := len(mchSetmouseW.FindAll(text, -1)); left != 2 {
		return nil, fmt.Errorf("nomouse: mch_setmouse has %d mentions left, expected the "+
			"definition and its declaration", left)
	}
	fmt.Fprintf(w, "  nomouse      %d setmouse() calls, every one a bare statement\n", 31)

	if text, err = cutCounted(text,
		`(?m)[ \t]*if \(tabcount > 1 && mouse_has_any\(\)\)\n[ \t]*\{\n`+
			`[ \t]*screen_putchar\('X', 0, \(int\)Columns - 1, attr_nosel\);\n`+
			`[ \t]*TabPageIdxs\[Columns - 1\] = -999;\n[ \t]*\}\n`,
		"nomouse", "draw_tabline()'s close button", 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nomouse      the tabline stops drawing a button to click")

	// :behave is about selection, not the mouse, so it keeps working; it just
	// stops setting an option that no longer exists.  Reached BY NAME, which
	// is the lookup that returns -1 for a row that is not there and then is
	// not checked -- E685 and a segfault before the first keystroke.
	if text, err = cutCounted(text,
		`(?m)^[ \t]*set_option_value_give_err\(\(char_u \*\)"mousemodel", 0L, `+
			`\(char_u \*\)"\w+", 0\);\n`,
		"nomouse", "ex_behave's two mousemodel lines", 2); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nomouse      :behave stops setting 'mousemodel'")

	// An option row is a ROOT for reachability, so did_set_ttymouse -- and
	// through it check_mouse_termcode() -- survives the sweep, and
	// did_set_string_option() still asks whether the option being set was
	// 'mouse'.  Both read p_mouse, so --strict refuses to drop the row; and
	// the row is what keeps them reachable.  The circle is broken here, by
	// hand, which is the honest place for it.
	if text, err = cutil.DropIf(text, `(?m)^[ \t]*if \(varp == &p_mouse\)$`, 1); err != nil {
		return nil, err
	}
	if text, err = cutCounted(text, `(?m)^[ \t]*check_mouse_termcode\(\);\n`,
		"nomouse", "did_set_ttymouse's call to check_mouse_termcode", 1); err != nil {
		return nil, err
	}
	var ok bool
	if text, ok = cutil.DeleteDefinition(text, "check_mouse_termcode"); !ok {
		return nil, fmt.Errorf("nomouse: check_mouse_termcode is not defined at file scope")
	}
	fmt.Fprintln(w, "  nomouse      the two p_mouse readers an option row kept reachable")

	if text, err = cutil.DropIf(text,
		`(?m)^[ \t]*if \(!option_was_set\(\(char_u \*\)"ttym"\) && \(term_props\[TPR_MOUSE\]`,
		1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nomouse      the terminal's mouse-protocol reply stops setting "+
		"'ttymouse'")

	if text, err = cutCounted(text,
		`(?m)^[ \t]*\(void\)opt_strings_flags\(p_ttym, p_ttym_values, &ttym_flags, FALSE\);\n`,
		"nomouse", "didset_string_options' p_ttym line", 1); err != nil {
		return nil, err
	}
	fmt.Fprintln(w, "  nomouse      didset_string_options stops reading 'ttymouse'")

	for _, name := range []string{"mouse", "mousemodel", "ttymouse"} {
		re := regexp.MustCompile(fmt.Sprintf(
			`(\(char_u \*\)&p_\w+, PV_NONE, )did_set_%s, expand_set_%s,`, name, name))
		var hit bool
		if text, hit = replaceFirst(re, text, "${1}NULL, NULL,"); !hit {
			return nil, fmt.Errorf("nomouse: '%s' does not name its two handlers", name)
		}
	}
	for _, name := range []string{"did_set_mouse", "expand_set_mouse", "did_set_mousemodel",
		"expand_set_mousemodel", "did_set_ttymouse", "expand_set_ttymouse"} {
		if text, ok = cutil.DeleteDefinition(text, name); !ok {
			return nil, fmt.Errorf("nomouse: %s is not defined at file scope", name)
		}
	}
	fmt.Fprintln(w, "  nomouse      the six option handlers their own rows kept reachable")

	// WaitForCharOrMouse() has no mouse in it: the name is left over from the
	// GUI build, where it also polled for motion events.  CHECKED rather than
	// assumed, and folded into WaitForChar(), its only caller, rather than
	// left telling a lie.
	o, c, found, balanced := cutil.Body(text, "WaitForCharOrMouse")
	if !found || !balanced {
		return nil, fmt.Errorf("nomouse: WaitForCharOrMouse is not defined at file scope")
	}
	inner := text[o+bytes.IndexByte(text[o:], '\n')+1 : bytes.LastIndexByte(text[:c], '\n')+1]
	innerCopy := append([]byte(nil), inner...)
	if anyMouse.Match(innerCopy) {
		return nil, fmt.Errorf("nomouse: WaitForCharOrMouse does mention the mouse after all")
	}
	if text, ok = cutil.DeleteDefinition(text, "WaitForCharOrMouse"); !ok {
		return nil, fmt.Errorf("nomouse: WaitForCharOrMouse would not delete")
	}
	o, c, found, balanced = cutil.Body(text, "WaitForChar")
	if !found || !balanced {
		return nil, fmt.Errorf("nomouse: WaitForChar is not defined at file scope")
	}
	if !bytes.Contains(text[o:c], []byte("WaitForCharOrMouse")) {
		return nil, fmt.Errorf("nomouse: WaitForChar does not forward to WaitForCharOrMouse")
	}
	buf = nil
	buf = append(buf, text[:o]...)
	buf = append(buf, "{\n"...)
	buf = append(buf, innerCopy...)
	buf = append(buf, '}')
	text = append(buf, text[c+1:]...)
	fmt.Fprintln(w, "  nomouse      WaitForCharOrMouse has no mouse in it; folded into "+
		"its one caller")

	fmt.Fprintf(w, "  nomouse      %d mouse mentions left for the sweep\n",
		len(anyMouse.FindAll(text, -1)))
	return text, nil
}
