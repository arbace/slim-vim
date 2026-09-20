package edit

import (
	"fmt"
	"io"
	"regexp"
	"sort"
	"strings"
)

var returnStub = regexp.MustCompile(`(?s)\Areturn\s+(.+);\z`)

// w79Constants are functions whose WHOLE body is `return <constant>;`.  The
// phase proves each one before folding anything that calls it: a stub that has
// acquired a body again would make every fold below change behaviour.
var w79Constants = map[string]string{
	"append_arg_number": "0", "at_ins_compl_key": "FALSE", "bomb_size": "0",
	"bt_quickfix": "FALSE", "bt_terminal": "FALSE",
	"check_can_set_curbuf_disabled": "TRUE", "check_can_set_curbuf_forceit": "TRUE",
	"check_more": "OK", "check_timestamps": "0", "current_tab_nr": "1",
	"current_win_nr": "1", "did_set_number_relativenumber": "NULL",
	"get_cellwidth": "0", "has_cursormoved": "FALSE", "has_insertcharpre": "FALSE",
	"has_textchanged": "FALSE", "in_vim9script": "FALSE", "ins_compl_active": "FALSE",
	"ins_compl_lnum_in_range": "FALSE", "ins_compl_win_active": "FALSE",
	"only_one_window": "TRUE", "pum_redraw_in_same_position": "FALSE",
	"pum_under_menu": "FALSE", "pum_visible": "FALSE", "script_get": "NULL",
	"stl_connected": "FALSE", "tabline_height": "0", "wc_use_keyname": "FALSE",
}

// w79Variable return a VARIABLE rather than a constant and are LEFT ALONE.  They
// are listed and checked so that the distinction is stated rather than assumed:
// folding one of these would freeze a value that still changes.
var w79Variable = map[string]string{
	"get_hislen": "hislen", "get_search_pat": "mr_pattern",
	"get_text_locked_msg": "e_not_allowed_to_change_text_or_change_window",
	"is_maphash_valid":    "maphash_valid",
}

// innerBody is a definition's body between the brace on its own line and the
// closing brace -- NOT the definition, which carries the parameter list.
func (e *E) innerBody(name string) (string, bool) {
	def, ok := e.BodyOf(name)
	if !ok {
		return "", false
	}
	s := string(def)
	i := strings.Index(s, "{\n")
	j := strings.LastIndex(s, "}")
	if i < 0 || j <= i {
		return "", false
	}
	return s[i+2 : j], true
}

// constOf requires name's whole body to be `return <expect>;` and nothing else.
func (e *E) constOf(name, expect string) {
	if e.Failed() {
		return
	}
	inner, ok := e.innerBody(name)
	if !ok {
		e.Refuse("%s is not defined", name)
		return
	}
	inner = strings.TrimSpace(inner)
	m := returnStub.FindStringSubmatch(inner)
	if m == nil {
		if len(inner) > 70 {
			inner = inner[:70]
		}
		e.Refuse("%s is no longer a one-line stub: %s", name, pyRepr(inner))
		return
	}
	if got := strings.TrimSpace(m[1]); got != expect {
		e.Refuse("%s returns %s, not %s -- folding it would change behaviour", name, pyRepr(got), pyRepr(expect))
	}
}

func pyRepr(s string) string { return "'" + s + "'" }

// sortedKeys is GENERIC in the map's value, because three of us wrote one each:
// whim79 over map[string]string, zero5 over map[string]int and zero27 over
// map[string]bool.  Ranging a Go map yields a different order every run, and
// every one of those three was written because a REPORT line is built from the
// keys -- which is the difference a boundary cannot see and editcmp can.
func sortedKeys[V any](m map[string]V) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// Whim79 folds every call to a function whose body is a constant.
func Whim79(text []byte, w io.Writer) ([]byte, error) {
	e := New("noconstfn", text, w)

	for _, n := range sortedKeys(w79Constants) {
		e.constOf(n, w79Constants[n])
	}
	if e.Failed() {
		return e.Done()
	}
	e.say(fmt.Sprintf("confirmed: %d functions whose whole body is `return <constant>;`", len(w79Constants)))
	for _, n := range sortedKeys(w79Variable) {
		e.constOf(n, w79Variable[n])
	}
	if e.Failed() {
		return e.Done()
	}
	e.say(fmt.Sprintf("confirmed: %d more return a VARIABLE and are left alone", len(w79Variable)))
	// THE SIGNATURE IS NOT THE BODY.  `long *wcp` is in the parameter list of
	// every version of this function, so asking the whole definition whether it
	// mentions wcp answers yes for ever and the check can never pass.  The
	// Python asks the INNER body -- from the `{` on its own line to the last
	// `}` -- which is what innerBody reproduces.
	if body, ok := e.innerBody("wc_use_keyname"); !ok || strings.Contains(body, "wcp") {
		e.Refuse("wc_use_keyname now mentions wcp -- it may write through the out-parameter")
		return e.Done()
	}
	e.say("confirmed: wc_use_keyname never dereferences its out-parameter")

	e.FoldNever(`(?m)^[ \t]*if \(vim9script && \(flags & DOCMD_RANGEOK\) == 0\)$`,
		"scanning backwards for a colon to decide whether a range is allowed")
	e.FoldNever(`(?m)^[ \t]*if \(vim9script && !may_have_range\)$`, "the Vim9 path through find_ex_command")
	e.FoldNeverCount(`(?m)^[ \t]*if \(vim9script\)$`, 2, "two Vim9 checks in parse_command_modifiers")
	e.FoldNever(`(?m)^[ \t]*if \(vim9script && has_cmdmod\(cmod, FALSE\)\)$`, "a command modifier without a command")
	e.term("(*p == '\"' && !vim9script && !(eap->argt & EX_NOTRLCOM)",
		"(*p == '\"' && !(eap->argt & EX_NOTRLCOM)", 1,
		"a double quote always starts a comment outside Vim9 script")
	e.term("(*p == '#' && vim9script && !(eap->argt & EX_NOTRLCOM) && p > eap->cmd &&  ((p[-1]) == ' ' || (p[-1]) == '\\t') ) || (*p == '|' && eap->cmdidx != CMD_append",
		"(*p == '|' && eap->cmdidx != CMD_append", 1, "and a hash never does")
	for _, indent := range []string{"", "    ", "        "} {
		e.Lines(`int `+indent+`vim9script = in_vim9script\(\);`, 1, "the local that recorded it")
	}
	e.FoldAlways(`(?m)^[ \t]*if \(may_have_range\)$`, "skipping a range that is always allowed")
	e.FoldNever(`(?m)^[ \t]*if \(!may_have_range\)$`, "the default address for a range that cannot be absent")
	e.Lines(`may_have_range = TRUE;`, 1, "the flag nothing decides any more")
	e.Lines(`int         may_have_range;`, 1, "and its declaration")
	e.FoldNever(`(?m)^[ \t]*if \(in_vim9script\(\) && \*p == '\\'' &&  \(\(unsigned\)\(p\[1\]\) - '0' < 10\) \)$`,
		"a digit separator in a Vim9 number literal")
	e.FoldNever(`(?m)^[ \t]*if \(in_vim9script\(\) && \*p == '#'\)$`, "a hash comment ending a Vim9 command")
	e.FoldNever(`(?m)^[ \t]*if \(in_vim9script\(\) && arg > arg_start && vim_strchr\(\(char_u \*\)"!&<", \*arg\) != NULL\)$`,
		"the Vim9 spacing rule for an unknown option")
	e.FoldNeverCount(`(?m)^[ \t]*if \(in_vim9script\(\)\)$`, 8, "eight more Vim9 script branches")
	e.term("in_vim9script() ? GETLINE_CONCAT_CONTBAR : GETLINE_CONCAT_CONT", "GETLINE_CONCAT_CONT", 1,
		"how a continuation line is joined")
	e.FoldNever(`(?m)^[ \t]*if \(pum_under_menu\(row, col, TRUE\)\)$`, "skipping a cell the popup menu covers")
	e.FoldNever(`(?m)^[ \t]*if \(pum_visible\(\) && \(State & MODE_CMDLINE\) == 0 && pum_under_menu\(row, col, FALSE\)\)$`,
		"and the same test on the command line")
	e.constOf("skip_for_popup", "FALSE")
	if !e.Failed() {
		e.say("confirmed: skip_for_popup has collapsed to `return FALSE;`")
	}
	e.term("may_trigger_safestate(ready && !ins_compl_active() && !pum_visible());",
		"may_trigger_safestate(ready);", 1, "whether a state is safe no longer asks about completion")
	e.FoldNeverCount(`(?m)^[ \t]*if \(pum_visible\(\)\)$`, 2, "two redraws deferred for the popup menu")
	e.FoldNever(`(?m)^[ \t]*if \(!ignore_pum && pum_visible\(\)\)$`, "the ruler deferred for it")
	e.FoldNever(`(?m)^[ \t]*if \(pum_redraw_in_same_position\(\)\)$`, "redrawing it in place")
	e.term(" || (!ignore_pum && pum_visible())", "", 1, "the status line deferred for it")
	e.term(" && !pum_visible())", ")", 1, "'relativenumber' redrawing around it")
	e.term(" && !ins_compl_active())", ")", 1, "'showmatch' suppressed during completion")
	e.FoldNeverCount(`(?m)^[ \t]*if \(\(State & MODE_INSERT\) && ins_compl_win_active\(wp\) && \(in_curline \|\| ins_compl_lnum_in_range\(lnum\)\)\)$`, 2,
		"two completion highlights in the line drawer")
	e.term(" && !at_ins_compl_key())", ")", 1, "a mapping suppressed by a completion key")
	e.FoldNever(`(?m)^[ \t]*if \(redraw_this && char_cells == 2 && skip_for_popup\(row, col \+ coloff \+ 1\)\)$`,
		"a double-width cell under the menu")
	e.FoldNever(`(?m)^[ \t]*if \(redraw_this && skip_for_popup\(row, col \+ coloff\)\)$`, "and a single-width one")
	e.term(" && !skip_for_popup(row, col + coloff))", ")", 1, "clearing the next cell")
	e.FoldAlways(`(?m)^[ \t]*if \(!skip_for_popup\(row, col \+ coloff\)\)$`, "drawing a screen line cell")
	e.FoldAlways(`(?m)^[ \t]*if \(!skip_for_popup\(row, col - 1\)\)$`, "redrawing the cell to the left")
	e.term(" && !skip_for_popup(row, col))", ")", 3, "three more cells that are never covered")
	e.FoldAlways(`(?m)^[ \t]*if \(!skip_for_popup\(r, c\)\)$`, "and filling a screen region")
	e.FoldAlways(`(?m)^[ \t]*if \(quit_all \|\| \(check_more\(FALSE, forceit\) == OK\)\)$`, "the autocommand check before quitting")
	e.FoldAlwaysCount(`(?m)^[ \t]*if \(check_more\(FALSE, eap->forceit\) == OK && only_one_window\(\)\)$`, 2,
		"deciding to exit in :quit and :exit")
	e.term(" || check_more(TRUE, eap->forceit) == FAIL", "", 2, "refusing to quit with more files to edit")
	e.term("only_one_window() && check_changed_any", "check_changed_any", 2, "and asking whether this is the last window")
	e.FoldNeverCount(`(?m)^[ \t]*if \(stl_connected\(wp\)\)$`, 2, "a status line joined to the one beside it")
	e.FoldNever(`(?m)^[ \t]*if \(get_cellwidth\(ScreenLinesUC\[off\]\) > 1\)$`, "a character widened by 'setcellwidths'")
	e.FoldNever(`(?m)^[ \t]*if \(wc_use_keyname\(varp, &wc\)\)$`, "showing a numeric option as a key name")
	e.FoldNever(`(?m)^[ \t]*if \(wc != 0\)$`, "and showing it as a character")
	e.FoldNever(`(?m)^[ \t]*if \(!check_can_set_curbuf_disabled\(\)\)$`, "refusing to change buffer in gf")
	e.FoldNever(`(?m)^[ \t]*if \(\(is_other_file\(0, ffname\) && !check_can_set_curbuf_forceit\(eap->forceit\)\)\)$`, "and refusing in :edit")
	e.term(" && !bt_terminal(wp->w_buffer)", "", 1, "the [+] flag suppressed for a terminal buffer")
	e.term(" && !bt_quickfix(curbuf)", "", 1, "a quickfix buffer never being reusable")
	e.term(" && !has_insertcharpre()", "", 1, "the InsertCharPre fast path")
	e.FoldNever(`(?m)^[ \t]*if \(!finish_op && \(has_cursormoved\(\)\) && ! `, "tracking the cursor for CursorMoved")
	e.FoldNever(`(?m)^[ \t]*if \(!finish_op && has_textchanged\(\) && `, "and the change tick for TextChanged")
	e.DropIfCount(`(?m)^[ \t]*if \(need_check_timestamps\)$`, 3, "three checks for a file changed outside the editor")
	e.Lines(`need_check_timestamps = TRUE;`, 1, "asking for one")
	e.Lines(`static int      need_check_timestamps  = FALSE ;`, 1, "and the flag itself")
	e.Lines(`need_redraw = check_timestamps\(FALSE\);`, 1, "the timestamp check on focus")
	e.FoldNever(`(?m)^[ \t]*if \(need_redraw\)$`, "and the redraw it asked for")
	e.Lines(`\(void\)append_arg_number\(curwin, \(char_u \*\)buffer \+ bufferlen,  \(1024\+1\)  - bufferlen, !shortmess\(SHM_FILE\)\);`, 1,
		"appending the argument-list position to the file message")
	e.term(w79lit1, w79lit2, 1, "reading a here-document for a command that cannot run")
	e.Lines(`bom_count = bomb_size\(\);`, 1, "counting the byte order mark")
	e.FoldNever(`(?m)^[ \t]*if \(dict == NULL && bom_count > 0\)$`, "and reporting it")
	e.term(w79lit3, w79lit4, 1, "the window-or-tab count for a bare range")
	for _, f := range []struct {
		fn, arg string
		n       int
	}{
		{"current_win_nr", "curwin", 3}, {"current_win_nr", "NULL", 3},
		{"current_tab_nr", "curtab", 3}, {"current_tab_nr", "NULL", 3},
	} {
		e.term(fmt.Sprintf("%s(%s)", f.fn, f.arg), "1", f.n,
			fmt.Sprintf("there is one window and one tabpage (%s(%s))", f.fn, f.arg))
	}
	e.term(w79lit5, w79lit6, 1, "the minimum rows needed, without a tab line")
	e.Lines(`total \+= tabline_height\(\);`, 1, "the tab line in the all-tabpages minimum")
	e.term("int         row = tabline_height();", "int         row = 0;", 1, "window layout starting at the top row")
	e.term("(Rows - p_ch - tabline_height())", "(Rows - p_ch)", 5, "five window heights with no tab line to subtract")
	e.term("tabline_height() + topframe->fr_height", "topframe->fr_height", 1, "and the 'cmdheight' consistency check")
	return e.Done()
}

func init() { register("whim79", Whim79) }
