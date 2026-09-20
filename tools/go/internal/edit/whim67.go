package edit

import (
	"fmt"
	"io"
	"regexp"
	"strings"
)

// The mouse names in key_names_table are matched ON THE NAME and not on the
// row's first field: five of eighteen -- DecMouse, JsbMouse, NetMouse,
// PtermMouse, UrxvtMouse -- are written with the key code first and a trailing
// FALSE across THREE lines, so an anchor on `{TRUE,` found 13 and left the
// terminal-specific ones behind, and a single-line pattern cannot see them at
// all.
var (
	mouseNameOneLine   = regexp.MustCompile(`(?m)^[ \t]*\{TRUE,[^\n]*\(char_u \*\)\("(\w*(?:Mouse|Drag|Release|Wheel)\w*)"\)[^\n]*\n`)
	mouseNameThreeLine = regexp.MustCompile(`(?m)^[ \t]*\{\n[ \t]*FALSE,\n[ \t]*[^\n]*\(char_u \*\)\("(\w*Mouse\w*)"\)[^\n]*\n`)
)

// writeOnlyStatics are file-scope variables that are written and never read,
// each with its writes.  Where the write is a whole `if` body or a whole
// function, that goes too -- see the three cases below the loop.
var writeOnlyStatics = []struct {
	decl, declWhat string
	writes         string
	n              int
	writesWhat     string
}{
	{`static int[ \t]+did_check_timestamps[ \t]*=[ \t]*FALSE[ \t]*;`, "did_check_timestamps", `did_check_timestamps = FALSE;`, 3, "the three writes to it"},
	{`static int[ \t]+did_emsg_syntax;`, "did_emsg_syntax", `did_emsg_syntax = (?:TRUE|FALSE);`, 2, "its two writes"},
	{`static int[ \t]+typebuf_was_empty[ \t]*=[ \t]*FALSE[ \t]*;`, "typebuf_was_empty", `typebuf_was_empty = (?:TRUE|FALSE);`, 2, "its two writes"},
	{`static volatile sig_atomic_t in_mch_delay = FALSE;`, "in_mch_delay", `in_mch_delay = (?:TRUE|FALSE);`, 2, "its two writes"},
}

// Whim67 takes the mouse -- every key name, the deferred-match machinery in
// check_termcode and the statics that tracked a pointer -- the spell plumbing
// win_line still carried, and eleven file-scope variables written and never
// read.
func Whim67(text []byte, w io.Writer) ([]byte, error) {
	e := New("nomouse", text, w)

	e.Literal(" || (is_mouse_key(n) && n !=   (-((KS_EXTRA) + ((int)(KE_LEFTMOUSE) << 8)))  )", "",
		"the input loop asking whether a key is a mouse key")
	e.Lines(`reset_dragwin\(\);`, 2, "the two calls that forgot the dragged window")
	e.Lines(`reset_held_button\(\);`, 1, "the call that forgot the held button")
	e.deleteDefinition("reset_dragwin", "reset_dragwin, which only cleared a dead pointer")
	e.deleteDefinition("reset_held_button", "reset_held_button, which only cleared a dead flag")
	e.Lines(`static win_T \*dragwin = NULL;`, 1, "dragwin itself")
	e.Lines(`static int[ \t]+held_button = MOUSE_RELEASE;`, 1, "held_button itself")
	// mouse_row/col and old_mouse_row/col are a closed loop: saved here,
	// restored there, read by nothing else.
	e.Lines(`static int[ \t]+mouse_row;`, 1, "mouse_row")
	e.Lines(`static int[ \t]+mouse_col;`, 1, "mouse_col")
	e.Lines(`static int old_mouse_row;`, 1, "old_mouse_row")
	e.Lines(`static int old_mouse_col;`, 1, "old_mouse_col")
	e.Lines(`mouse_row = old_mouse_row;`, 1, "restoring the mouse row")
	e.Lines(`mouse_col = old_mouse_col;`, 1, "restoring the mouse column")
	e.Lines(`old_mouse_row = mouse_row;`, 1, "saving the mouse row")
	e.Lines(`old_mouse_col = mouse_col;`, 1, "saving the mouse column")

	if !e.Failed() {
		one := names(mouseNameOneLine, e.Text())
		if len(one) != 13 {
			e.Refuse("key_names_table -- %d single-line mouse names, expected 13: %s", len(one), strings.Join(one, " "))
		} else {
			e.Cut(mouseNameOneLine.String(), 13, "the mouse key names: "+strings.Join(one, " "))
		}
	}
	if !e.Failed() {
		three := names(mouseNameThreeLine, e.Text())
		if len(three) != 5 {
			e.Refuse("key_names_table -- %d three-line mouse names, expected 5: %s", len(three), strings.Join(three, " "))
		} else {
			e.Cut(mouseNameThreeLine.String(), 5, "the terminal-specific mouse names: "+strings.Join(three, " "))
		}
	}
	e.Cut(`(?m)^[ \t]*\{  \(-\(\(KS_MOUSE\) \+ \(\(int\)\( \('X'\) \) << 8\)\)\)  ,[^\n]*"\[MOUSE\]"\},\n`, 1,
		"the [MOUSE] entry of the terminal string table")

	e.InFunction("check_termcode", func(e *E) {
		e.Lines(`int  mouse_index_found = -1;`, 1, "check_termcode remembering a deferred mouse match")
		e.Lines(`int     looks_like_mouse_start = FALSE;`, 1, "check_termcode deferring an ESC [ match")
		// The whole `slen == 2 && ESC [` block existed to set that flag, and its
		// only other arm counted the semicolons of a DEC mouse report.
		e.DropIf(`(?m)^[ \t]*if \(slen == 2 && len > 2 && termcodes\[idx\]\.code\[0\] == ESC && termcodes\[idx\]\.code\[1\] == '\['\)$`,
			"deferring an ESC [ code in case a mouse code is longer")
		e.FoldNever(`(?m)^[ \t]*if \(looks_like_mouse_start\)$`, "a deferred match winning over a real one")
		e.Literal(" && mouse_index_found < 0", "", "the modifier scan waiting for a deferred mouse match")
		e.FoldNever(`(?m)^[ \t]*else if \(idx == tc_len && mouse_index_found >= 0\)$`, "falling back to the deferred mouse match")
		e.Cut(`(?m)^[ \t]*if \(key_name\[0\] == KS_MOUSE \|\| key_name\[0\] == KS_SGR_MOUSE \|\| key_name\[0\] == KS_SGR_MOUSE_RELEASE\)\n[ \t]*\{\n[ \t]*\}\n\n?`, 1,
			"a mouse report being handled by an empty block")
	})

	// the spell plumbing
	e.Literal(", spellvars_T *spv  __attribute__((unused)) )", ")", "win_line's unused spell parameter")
	e.Lines(`spellvars_T spv;`, 1, "the spell variables win_update kept on the stack")
	e.Literal("win_line(wp, lnum, srow, wp->w_height, 0, &spv)", "win_line(wp, lnum, srow, wp->w_height, 0)", "the first win_line call")
	e.Literal("win_line(wp, lnum, srow, wp->w_height, wp->w_lines[idx].wl_size, &spv)",
		"win_line(wp, lnum, srow, wp->w_height, wp->w_lines[idx].wl_size)", "the second win_line call")
	e.Cut(`(?m)^typedef struct \{\n[ \t]*int[ \t]+spv_has_spell;\n\} spellvars_T;\n\n?`, 1, "spellvars_T itself")

	// the write-only statics
	for _, s := range writeOnlyStatics {
		e.Lines(s.decl, 1, s.declWhat)
		e.Lines(s.writes, s.n, s.writesWhat)
	}
	e.Lines(`static int[ \t]+frame_locked = 0;`, 1, "frame_locked")
	e.Lines(`frame_locked\+\+;`, 1, "the lock it took")
	e.Lines(`frame_locked--;`, 1, "the lock it released")
	e.Lines(`static int[ \t]+swap_exists_did_quit[ \t]*=[ \t]*FALSE[ \t]*;`, 1, "swap_exists_did_quit")
	e.Lines(`swap_exists_did_quit = TRUE;`, 1, "its one write")
	e.Lines(`static int[ \t]+did_swapwrite_msg[ \t]*=[ \t]*FALSE[ \t]*;`, 1, "did_swapwrite_msg")
	e.Lines(`did_swapwrite_msg = FALSE;`, 1, "its one write")
	e.Lines(`static int[ \t]+autocmd_nested = FALSE;`, 1, "autocmd_nested")
	e.Lines(`autocmd_nested = ac->nested;`, 1, "its one write")
	e.Lines(`static volatile sig_atomic_t oldtitle_outdated = FALSE;`, 1, "oldtitle_outdated")
	e.Lines(`oldtitle_outdated = TRUE;`, 1, "its one write")
	e.Lines(`static volatile sig_atomic_t deadly_signal = 0;`, 1, "deadly_signal")
	e.Lines(`deadly_signal = sigarg;`, 1, "the signal number it recorded")
	// mr_patternlen's two writes are a whole if/else, so the test goes with them.
	e.Cut(`(?m)^[ \t]*if \(mr_pattern == NULL\)\n[ \t]*\{\n[ \t]*mr_patternlen = 0;\n[ \t]*\}\n[ \t]*else\n[ \t]*\{\n[ \t]*mr_patternlen = patlen;\n[ \t]*\}\n`, 1,
		"mr_patternlen's if/else")
	e.Lines(`static size_t[ \t]+mr_patternlen = 0;`, 1, "mr_patternlen")
	// was_safe is a whole function body, and that function has two callers.
	e.Lines(`state_no_longer_safe\("(?:ins_typebuf\(\)|key typed)"\);`, 2, "the two calls that declared the state unsafe")
	e.deleteDefinition("state_no_longer_safe", "state_no_longer_safe, whose body was one write")
	e.Lines(`static int[ \t]+was_safe = FALSE;`, 1, "was_safe")
	e.Lines(`was_safe = (?:is_safe|FALSE);`, 2, "its remaining writes")
	return e.Done()
}

// names returns the first capture of every match, which is how this phase builds
// the report line that lists what it removed.
func names(re *regexp.Regexp, text []byte) []string {
	var out []string
	for _, m := range re.FindAllSubmatch(text, -1) {
		out = append(out, string(m[1]))
	}
	return out
}

var _ = fmt.Sprintf

func init() { register("whim67", Whim67) }
