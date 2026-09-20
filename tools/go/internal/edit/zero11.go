package edit

import (
	"io"
	"regexp"
	"strconv"
	"strings"

	"slimvim.local/tools/internal/cutil"
)

func init() { register("zero11", Zero11) }

// z11Swept are the twelve the sweep reads out of check_changed_any's tail, and
// they are mostly three mentions each -- a prototype, a definition and one call.
// THREE OF THEM ARE NOT, which is what a counted anchor is for, and those three
// are named in z11Before instead.
var z11Swept = []string{"no_write_message", "add_bufnum", "set_curbuf", "enter_buffer",
	"win_enter", "win_enter_ext", "goto_tabpage_win", "goto_tabpage_tp", "get_winopts",
	"find_wininfo", "buflist_findfpos", "buflist_getfpos"}

// z11Island is the switch-buffer/switch-window island that hangs off that tail.
// IT IS A GRAPH AND NOT A FAN: only add_bufnum, set_curbuf and goto_tabpage_win
// are called by check_changed_any itself and the other eight hang off those, so
// a check requiring all eleven to be its callees would fail on a correct phase.
var z11Island = []string{"add_bufnum", "set_curbuf", "enter_buffer", "win_enter",
	"win_enter_ext", "goto_tabpage_win", "goto_tabpage_tp", "get_winopts",
	"find_wininfo", "buflist_findfpos", "buflist_getfpos"}

var z11Before = map[string]int{
	"check_changed": 4, "not_exiting": 4,
	"check_changed_any": 2, "no_write_message_nobang": 2,
	"w_topline_was_set": 4, "wi_changelistidx": 3, "SHM_FILEINFO": 2,
	"bufIsChanged": 10, "curbufIsChanged": 7, "bufIsChangedNotTerm": 3,
	"exiting": 17, "buf_spname": 5, "open_buffer": 5,
	"curbuf_locked": 7, "text_locked": 6, "before_quit_autocmds": 2,
	"p_ro": 2, "p_ur": 2, "read_cmd_fd": 12,
	"vim_fsync": 3, "scriptin": 8, "redir_fd": 6,
}

var z11After = map[string]int{
	"check_changed": 3, "not_exiting": 2,
	"w_topline_was_set": 2, "wi_changelistidx": 1,
	"bufIsChanged": 10, "curbufIsChanged": 7, "bufIsChangedNotTerm": 3,
	"curbuf_locked": 7, "text_locked": 6, "before_quit_autocmds": 2,
	"p_ro": 2, "p_ur": 2, "read_cmd_fd": 12,
	"vim_fsync": 3, "scriptin": 8, "redir_fd": 6,
}

func init() {
	for _, n := range z11Swept {
		z11Before[n] = 3
	}
}

// Zero11 takes the last thing the filesystem left behind: the refusal,
// `E37: No write since last change`, which has had no remedy to offer since
// phase 6 took every `:write`.
func Zero11(text []byte, w io.Writer) ([]byte, error) {
	p := ph{"noquit", w}
	var err error

	mentions := func(t []byte, name string) int {
		return len(regexp.MustCompile(`\b`+name+`\b`).FindAll(t, -1))
	}
	textEdit := func(t []byte, old, new, what string, n int) ([]byte, error) {
		k := strings.Count(string(t), old)
		if k != n {
			return nil, p.die("%s -- the text occurs %d times, expected %d: %s",
				what, k, n, cutil.PyRepr(zHead(old, 70)))
		}
		p.say(what)
		return []byte(strings.ReplaceAll(string(t), old, new)), nil
	}

	// ---- 0. the shape every anchor below was counted against ------------------
	for _, name := range sortedKeys(z11Before) {
		if k := mentions(text, name); k != z11Before[name] {
			return nil, p.die("%s has %d mentions, expected %d -- the anchors below were counted "+
				"against a different file", name, k, z11Before[name])
		}
	}
	p.say("check_changed 4, not_exiting 4, check_changed_any 2 and the twelve the " +
		"sweep reads from it -- the file the one fold was counted against")

	// THE INVARIANT, COMPUTED BEFORE ANYTHING IS FOLDED: every call to any of the
	// eleven is inside check_changed_any or inside another of the eleven, so the
	// whole island is reachable from that one tail and from nowhere else.
	blanked := cutil.Blank(text)
	spans := map[string][2]int{}
	for _, name := range append(append([]string{}, z11Island...), "check_changed_any") {
		a, z, ok := cutil.FindDefinition(text, blanked, name)
		if !ok {
			return nil, p.die("%s is not defined", name)
		}
		spans[name] = [2]int{a, z}
	}
	for _, name := range z11Island {
		own := spans[name]
		proto := regexp.MustCompile(`^static\b.*\b` + name + `\(.*\);$`)
		calls, stray := 0, []int{}
		for _, m := range regexp.MustCompile(`\b`+name+`\b`).FindAllIndex(text, -1) {
			if own[0] <= m[0] && m[0] < own[1] {
				continue // inside its own definition
			}
			s := strings.LastIndex(string(text[:m[0]]), "\n") + 1
			e := strings.Index(string(text[m[0]:]), "\n") + m[0]
			if proto.MatchString(strings.TrimSpace(string(text[s:e]))) {
				continue // its prototype
			}
			calls++
			in := false
			for _, sp := range spans {
				if sp[0] <= m[0] && m[0] < sp[1] {
					in = true
					break
				}
			}
			if !in {
				stray = append(stray, strings.Count(string(text[:m[0]]), "\n")+1)
			}
		}
		if calls == 0 || len(stray) > 0 {
			first := "-"
			if len(stray) > 0 {
				first = strconv.Itoa(stray[0])
			}
			return nil, p.die("%s has %d call site(s) and %d of them are outside check_changed_any "+
				"and the island (first at line %s); the switch-buffer island does not "+
				"hang off that one tail after all", name, calls, len(stray), first)
		}
	}
	p.say("every call to add_bufnum, set_curbuf, enter_buffer, win_enter, win_enter_ext, " +
		"goto_tabpage_win, goto_tabpage_tp, get_winopts, find_wininfo, buflist_findfpos " +
		"and buflist_getfpos is inside check_changed_any or inside another of the " +
		"eleven -- its tail, \"go to the buffer that refused\", is the last caller of the " +
		"whole switch-buffer/switch-window island, and that, and nothing weaker, is why " +
		"the one fold below takes eleven functions nobody would predict")

	// ---- 1. the anchor: the refusal folds never -------------------------------
	a, z, ok := cutil.FindDefinition(text, cutil.Blank(text), "ex_quit")
	if !ok {
		return nil, p.die("ex_quit is not defined")
	}
	what := "ex_quit: the refusal folds NEVER, so `:q` takes the else arm and quits -- " +
		"this one fold is the phase, and it is check_changed()'s last reference"
	body, err := cutil.FoldNever(text[a:z],
		`(?m)^    if \(\(check_changed\(wp->w_buffer, \(eap->forceit \? CCGD_FORCEIT : 0\) \| CCGD_EXCMD\)\) \|\| \(check_changed_any\(eap->forceit, TRUE\)\)\)$`, 1)
	if err != nil {
		return nil, p.die("%s -- %v", what, err)
	}
	text = []byte(string(text[:a]) + string(body) + string(text[z:]))
	p.say(what)

	// ---- 2. extra B: the tail that cannot run ---------------------------------
	if text, err = textEdit(text, z11lit1, z11lit2,
		"ex_quit's tail: getout() sets `exiting = TRUE` itself and ends in "+
			"mch_exit(), which never returns, so the save, the set and the "+
			"restore are dead -- and not_exiting(), which was the whole of \"we "+
			"changed our mind, put the terminal back\", has no caller left", 1); err != nil {
		return nil, err
	}
	if k := mentions(text, "not_exiting"); k != 2 {
		return nil, p.die("not_exiting has %d mentions, expected 2 -- its prototype and its "+
			"definition, for the sweep", k)
	}

	// ---- 3. extra A: two fields that become write-only ------------------------
	// NOTHING SEES EITHER OF THESE.  deadfields.py removes a field nothing NAMES,
	// and a field that is only written is still named; gcc has no warning for one.
	for _, fr := range []struct{ fld, reader string }{
		{"w_topline_was_set", "enter_buffer"}, {"wi_changelistidx", "get_winopts"},
	} {
		a, z, ok := cutil.FindDefinition(text, cutil.Blank(text), fr.reader)
		if !ok || !strings.Contains(string(text[a:z]), fr.fld) {
			return nil, p.die("%s is not named inside %s, and the sweep taking that function is the "+
				"whole reason this field becomes write-only", fr.fld, fr.reader)
		}
	}
	for _, e := range []struct{ old, what string }{
		{z11lit3, "win_T.w_topline_was_set: its only reader is inside enter_buffer(), " +
			"which the sweep takes -- so the field is write-only and nothing sees it"},
		{z11lit4, "and its one surviving write, in set_topline()"},
		{z11lit5, "wininfo_S.wi_changelistidx: its only reader is inside get_winopts(), " +
			"swept with the rest of the island"},
		{z11lit6, "and its one surviving write, in find_wininfo() -- which the sweep " +
			"takes too, so this line is removed for what it says and not for what " +
			"it costs"},
	} {
		if text, err = textEdit(text, e.old, "", e.what, 1); err != nil {
			return nil, err
		}
	}

	// ---- what the sweep is handed, as a count rather than as trust ------------
	for _, name := range sortedKeys(z11After) {
		if k := mentions(text, name); k != z11After[name] {
			return nil, p.die("%s has %d mentions after the cut, expected %d", name, k, z11After[name])
		}
	}
	p.say("the cut is done: check_changed 3 -- its prototype, its definition and the " +
		"one call inside check_changed_any, which is where the sweep starts -- " +
		"not_exiting 2, and read_cmd_fd 12, vim_fsync 3, scriptin 8 and redir_fd 6 " +
		"untouched, each of them a later phase's")
	return text, nil
}
