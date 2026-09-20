package edit

import (
	"bytes"
	"fmt"
	"io"
	"regexp"
)

// key and kex spell the two ways this file writes a special key as an integer.
// They are built rather than written out because the C is a nest of escaped
// parentheses and the same shape recurs: KEY('k','B') is S-Tab, KEX(KE_WILD) is
// the wildcard trigger.
func key(a, b string) string {
	return fmt.Sprintf(`\(-\(\('%s'\) \+ \(\(int\)\('%s'\) << 8\)\)\)`, a, b)
}

func kex(k string) string {
	return fmt.Sprintf(`\(-\(\(KS_EXTRA\) \+ \(\(int\)\(%s\) << 8\)\)\)`, k)
}

var (
	optionsTableStart = regexp.MustCompile(`(?m)^[ \t]*\{"ambiwidth",`)
	valueCompletion   = regexp.MustCompile(`\bexpand_set_\w+(\s*,)`)
	noFileMatches     = regexp.MustCompile(`(?m)^    \*matches = \(char_u \*\*\)"";\n`)
)

// Whim59 takes command-line completion: the wildcard machinery in
// getcmdline_int, every options[] row's value-completion callback, and every
// context ExpandFromContext knew but files.
func Whim59(text []byte, w io.Writer) ([]byte, error) {
	e := New("nocompletion", text, w)

	e.InFunction("getcmdline_int", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(ccline\.cmdbuff_replaced && xpc\.xp_numfiles > 0\)$`,
			"a replaced command line freeing its matches")
		e.DropIf(fmt.Sprintf(`(?m)^[ \t]*if \(c == [ \t]*%s[ \t]*&& did_hist_navigate\)$`, kex("KE_WILD")),
			"a wildcard trigger after history navigation")
		e.Cut(`(?m)^[ \t]*did_hist_navigate = TRUE;\n`, 1,
			"history navigation remembered for the wildcard trigger")
		e.DropIf(fmt.Sprintf(`(?m)^[ \t]*if \(c != p_wc && c == [ \t]*%s[ \t]*&& xpc\.xp_numfiles > 0\)$`, key("k", "B")),
			"S-Tab stepping back through matches")
		e.Cut(`(?m)^[ \t]*int key_is_wc = [^\n]*;\n`, 1, "the 'wildchar' key test")
		e.DropIf(`(?m)^[ \t]*if \(\(did_wild_list\) && !key_is_wc && xpc\.xp_numfiles > 0\)$`,
			"CTRL-E and CTRL-Y over a match list")
		e.DropIf(`(?m)^[ \t]*if \(\(c == ESC \|\| c == Ctrl_C\) && \(wim_flags\[0\] & WIM_LIST\)\)$`,
			"leaving a 'wildmode' list clearing 'hlsearch'")
		e.Cut(`(?m)^[ \t]*end_wildmenu = \([^\n]*\);\n`, 1, "deciding the match list ends")
		e.DropIf(`(?m)^[ \t]*if \(end_wildmenu\)$`, "ending the match list")
		e.DropIf(fmt.Sprintf(`(?m)^[ \t]*if \(\(c == p_wc && !gotesc && KeyTyped\) \|\| c == p_wcm \|\| c == [ \t]*%s[ \t]*\)$`, kex("KE_WILD")),
			"completing on 'wildchar', 'wildcharm' or the wildcard trigger")
		e.DropIf(fmt.Sprintf(`(?m)^[ \t]*if \(c == [ \t]*%s[ \t]*&& KeyTyped\)$`, key("k", "B")),
			"S-Tab completing backwards")
		e.Cut(`(?m)^[ \t]*case Ctrl_D:\n[ \t]*if \(showmatches\(&xpc, TRUE\) == EXPAND_NOTHING\)\n[ \t]*\{\n[ \t]*break;\n[ \t]*\}\n\n?[ \t]*redrawcmd\(\);\n[ \t]*continue;\n\n?`,
			1, "CTRL-D listing matches")
		e.Cut(`(?m)^[ \t]*case Ctrl_A:\n[ \t]*if \(nextwild\(&xpc, WILD_ALL, 0, firstc != '@'\) == FAIL\)\n[ \t]*\{\n[ \t]*break;\n[ \t]*\}\n[ \t]*xpc\.xp_context = EXPAND_NOTHING;\n[ \t]*did_wild_list = FALSE;\n[ \t]*goto cmdline_changed;\n\n?`,
			1, "CTRL-A inserting every match")
		e.Sub(`(?m)^([ \t]*)if \(nextwild\(&xpc, WILD_LONGEST, 0, firstc != '@'\) == FAIL\)\n[ \t]*\{\n[ \t]*break;\n[ \t]*\}\n[ \t]*goto cmdline_changed;\n`,
			"${1}break;\n", 1, "CTRL-L completing the longest match")
		e.DropIf(`(?m)^[ \t]*if \(xpc\.xp_numfiles > 0\)$`, "CTRL-N and CTRL-P stepping through matches")
		e.Cut(`(?m)^[ \t]*did_wild_list = FALSE;\n[ \t]*wim_index = 0;\n`, 1,
			"leaving the command line resetting the match list")
		e.Literal("may_trigger_safestate(xpc.xp_numfiles <= 0);", "may_trigger_safestate(TRUE);",
			"SafeState not waiting on a match list")
		e.Literal("if (xpc.xp_context == EXPAND_NOTHING && (KeyTyped || vpeekc() == NUL))",
			"if (KeyTyped || vpeekc() == NUL)",
			"incremental search not waiting on a completion context")
	})

	// Each options[] row names a callback that completes its value, called only
	// by :set completion, which is gone -- but the table keeps them reachable,
	// and with them ExpandGeneric() and the fuzzy matcher.  The row's callback
	// becomes NULL.  The count is a FLOOR rather than a number: how many rows
	// carry one is a fact about a table other phases are also cutting, and a
	// floor refuses the case this guards against -- a pattern that has stopped
	// matching.
	if !e.Failed() {
		t := e.Text()
		m := optionsTableStart.FindIndex(t)
		if m == nil {
			e.die("options[] does not start at \"ambiwidth\"")
		} else if z := bytes.Index(t[m[0]:], []byte("\n};")); z < 0 {
			e.die("options[] does not end")
		} else {
			a, z := m[0], m[0]+z
			k := len(valueCompletion.FindAll(t[a:z], -1))
			if k < 20 {
				e.die("options[] names %d value-completion callbacks, expected many", k)
			} else {
				out := append([]byte{}, t[:a]...)
				out = append(out, valueCompletion.ReplaceAll(t[a:z], []byte("NULL$1"))...)
				e.Set(append(out, t[z:]...))
				e.say(fmt.Sprintf("options[] no longer names a value-completion callback (%d rows)", k))
			}
		}
	}

	e.InFunction("ExpandFromContext", func(e *E) {
		// The non-file contexts are one run, from the empty-match assignment to
		// the function's last `return ret;`.  It is cut by its ends rather than
		// by a pattern over the whole span: the run is hundreds of lines of
		// unrelated cases, and a regular expression that matched all of them
		// would match anything.
		if e.Failed() {
			return
		}
		t := e.Text()
		m := noFileMatches.FindIndex(t)
		tail := []byte("\n    return ret;\n")
		z := bytes.LastIndex(t, tail)
		if m == nil || z < 0 {
			e.die("ExpandFromContext -- the non-file contexts were not found")
			return
		}
		out := append([]byte{}, t[:m[0]]...)
		e.Set(append(out, t[z+len(tail):]...))
		e.say("every completion context but files")
		e.FoldAlways(`(?m)^[ \t]*if \(xp->xp_context == EXPAND_FILES \|\| xp->xp_context == EXPAND_DIRECTORIES \|\| xp->xp_context == EXPAND_FILES_IN_PATH \|\| xp->xp_context == EXPAND_FINDFUNC \|\| xp->xp_context == EXPAND_DIRS_IN_CDPATH\)$`,
			"file expansion is the only context")
	})

	e.InFunction("ExpandOne", func(e *E) {
		e.FoldNever(`(?m)^[ \t]*if \(mode == WILD_NEXT \|\| mode == WILD_PREV \|\| mode == WILD_PAGEUP \|\| mode == WILD_PAGEDOWN\)$`,
			"ExpandOne stepping through matches")
		e.FoldNever(`(?m)^[ \t]*if \(mode == WILD_CANCEL\)$`, "ExpandOne cancelling or applying a match")
		e.FoldNever(`(?m)^[ \t]*if \(mode == WILD_FREE\)$`, "ExpandOne only freeing")
		e.FoldNever(`(?m)^[ \t]*if \(mode == WILD_LONGEST && xp->xp_numfiles > 0\)$`, "ExpandOne finding the longest match")
		e.FoldNever(`(?m)^[ \t]*if \(mode == WILD_ALL && xp->xp_numfiles > 0 && !got_int\)$`, "ExpandOne joining every match")
		e.FoldAlways(`(?m)^[ \t]*if \(mode == WILD_EXPAND_FREE \|\| mode == WILD_ALL\)$`, "ExpandOne always cleaning up after expanding")
	})

	e.InFunction("didset_options2", func(e *E) {
		e.Cut(`(?m)^[ \t]*check_opt_wim\(\);\n\n?`, 1, "startup parsing 'wildmode' into flags nothing reads")
	})
	e.InFunction("expand_filename", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(p_wic\)$`, "'wildignorecase' in filename globbing")
	})
	e.InFunction("expand_wildcards", func(e *E) {
		e.DropIf(`(?m)^[ \t]*if \(\*p_wig\)$`, "'wildignore' in filename globbing")
	})
	e.InFunction("do_set_option_numeric", func(e *E) {
		e.FoldNever(`(?m)^[ \t]*else if \(\(\(long \*\)varp == &p_wc \|\| \(long \*\)varp == &p_wcm\)`, ":set wc= accepting a key name")
	})
	e.InFunction("wc_use_keyname", func(e *E) {
		e.FoldNever(`(?m)^[ \t]*if \(\(\(long \*\)varp == &p_wc\) \|\| \(\(long \*\)varp == &p_wcm\)\)$`, ":set wc? showing a key name")
	})
	return e.Done()
}

func init() { register("whim59", Whim59) }
