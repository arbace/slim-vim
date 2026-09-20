package cut

import (
	"bytes"
	"fmt"
	"io"
	"regexp"

	"slimvim.local/tools/internal/cutil"
)

// wmCut is edits applied in order, each of which must find exactly what it
// expects, with the report printed at the END rather than as it goes.
//
// A miss is fatal rather than silent.  An edit that quietly matched nothing
// leaves the code it was meant to remove in place, and the report still says
// the phase succeeded -- which is how an inert option survives three passes.
type wmCut struct {
	text []byte
	log  []struct {
		what string
		n    int
	}
}

func (c *wmCut) note(what string, n int) {
	c.log = append(c.log, struct {
		what string
		n    int
	}{what, n})
}

func (c *wmCut) sub(pat, repl string, count int, what string) error {
	re := regexp.MustCompile("(?m)" + pat)
	n := len(re.FindAll(c.text, -1))
	if n != count {
		return fmt.Errorf("nowildmenu: %s -- expected %d, matched %d", what, count, n)
	}
	c.text = re.ReplaceAll(c.text, []byte(repl))
	c.note(what, n)
	return nil
}

// block returns (line_start, open_brace, close_brace) for the `if (...)`
// matching pat.
//
// The extent of the condition is found by MATCHING PARENTHESES, not by reading
// to the end of the line: these conditions are single-line by construction but
// full of parenthesised key codes, so a pattern that merely names the first
// term stops in the middle of one.
func (c *wmCut) block(pat string) (start, opening, closing int, ok bool) {
	m := regexp.MustCompile("(?m)" + pat).FindIndex(c.text)
	if m == nil {
		return 0, 0, 0, false
	}
	blanked := cutil.Blank(c.text)
	lp := m[0] + bytes.IndexByte(c.text[m[0]:], '(')
	rp := cutil.Match(blanked, lp)
	if rp < 0 {
		return 0, 0, 0, false
	}
	i := rp + 1
	for i < len(c.text) && (c.text[i] == ' ' || c.text[i] == '\t' || c.text[i] == '\n') {
		i++
	}
	if i >= len(c.text) || c.text[i] != '{' {
		return 0, 0, 0, false
	}
	cl := cutil.Match(blanked, i)
	if cl < 0 {
		return 0, 0, 0, false
	}
	return m[0], i, cl, true
}

func (c *wmCut) blockEnd(closing int) int {
	end := closing + 1
	for end < len(c.text) && (c.text[end] == ' ' || c.text[end] == '\t') {
		end++
	}
	if end < len(c.text) && c.text[end] == '\n' {
		end++
	}
	if end < len(c.text) && c.text[end] == '\n' {
		end++
	}
	return end
}

// dropIf deletes an `if (...)` and everything it guards, count times, and then
// requires that there are no more.
func (c *wmCut) dropIf(pat string, count int, what string) error {
	for i := 0; i < count; i++ {
		start, _, closing, ok := c.block(pat)
		if !ok {
			return fmt.Errorf("nowildmenu: %s -- no more blocks to drop", what)
		}
		end := c.blockEnd(closing)
		out := make([]byte, 0, len(c.text))
		out = append(out, c.text[:start]...)
		c.text = append(out, c.text[end:]...)
	}
	if _, _, _, ok := c.block(pat); ok {
		return fmt.Errorf("nowildmenu: %s -- more blocks than expected", what)
	}
	c.note(what, count)
	return nil
}

// unwrapIf deletes an `if (...)`'s header and braces, keeping its body.
func (c *wmCut) unwrapIf(pat string, count int, what string) error {
	for i := 0; i < count; i++ {
		start, opening, closing, ok := c.block(pat)
		if !ok {
			return fmt.Errorf("nowildmenu: %s -- no more blocks to unwrap", what)
		}
		body := cutil.Dedent4(c.text[opening+bytes.IndexByte(c.text[opening:], '\n')+1 : bytes.LastIndexByte(c.text[:closing], '\n')+1])
		end := closing + 1
		for end < len(c.text) && (c.text[end] == ' ' || c.text[end] == '\t') {
			end++
		}
		if end < len(c.text) && c.text[end] == '\n' {
			end++
		}
		out := make([]byte, 0, len(c.text))
		out = append(out, c.text[:start]...)
		out = append(out, body...)
		c.text = append(out, c.text[end:]...)
	}
	c.note(what, count)
	return nil
}

// keepElse turns `if (dead) { A } else { B }` into B.
func (c *wmCut) keepElse(pat, what string) error {
	start, _, closing, ok := c.block(pat)
	if !ok {
		return fmt.Errorf("nowildmenu: %s -- not found", what)
	}
	m := regexp.MustCompile(`^[ \t]*\n[ \t]*else[ \t]*\n`).FindIndex(c.text[closing+1:])
	if m == nil {
		return fmt.Errorf("nowildmenu: %s -- no else branch, so there is nothing to "+
			"keep and deleting the if alone would delete the fallback", what)
	}
	blanked := cutil.Blank(c.text)
	at := closing + 1 + m[1]
	opening := at + bytes.IndexByte(blanked[at:], '{')
	eclose := cutil.Match(blanked, opening)
	if eclose < 0 {
		return fmt.Errorf("nowildmenu: %s -- the else branch is unbalanced", what)
	}
	body := cutil.Dedent4(c.text[opening+bytes.IndexByte(c.text[opening:], '\n')+1 : bytes.LastIndexByte(c.text[:eclose], '\n')+1])
	end := eclose + 1
	for end < len(c.text) && (c.text[end] == ' ' || c.text[end] == '\t') {
		end++
	}
	if end < len(c.text) && c.text[end] == '\n' {
		end++
	}
	out := make([]byte, 0, len(c.text))
	out = append(out, c.text[:start]...)
	out = append(out, body...)
	c.text = append(out, c.text[end:]...)
	c.note(what, 1)
	return nil
}

// NoWildMenu removes 'wildmenu' and the command-line popup it drew.
func NoWildMenu(text []byte, w io.Writer) ([]byte, error) {
	c := &wmCut{text: text}
	steps := []func() error{
		func() error { return c.dropIf(`^[ \t]*if \(p_wmnu\)[ \t]*$`, 3, "the three `if (p_wmnu)` blocks") },
		func() error {
			return c.unwrapIf(`^[ \t]*if \(!p_wmnu \|\| \(c != `, 1,
				"the cmdline_leave guard that only wildmenu needed")
		},
		// showmatches' second argument was "draw the wildmenu" and its fourth
		// the wildmode flags that only the menu read.  ONE substitution covers
		// the definition, the prototype and all six calls, because they have
		// the same shape.
		func() error {
			return c.sub(`\bshowmatches\(([^,]+), [^,]+, ([^,]+), [^)]*\)`,
				"showmatches(${1}, ${2})", 7,
				"showmatches loses its wildmenu and wim_flags arguments")
		},
		func() error {
			return c.sub(`^[ \t]*int         noselect = \(wim_flags_arg & WIM_NOSELECT\);\n`+
				`[ \t]*int         noinsert = \(wim_flags_arg & WIM_NOINSERT\);\n`+
				`[ \t]*int         cmdline_unchanged = noselect \|\| noinsert;\n`, "", 1,
				"showmatches drops the three locals only the menu read")
		},
		func() error {
			return c.dropIf(`^[ \t]*if \(display_wildmenu && !display_list && vim_strchr`, 1,
				"the popup form of the wildmenu")
		},
		func() error {
			return c.dropIf(`^[ \t]*if \(display_wildmenu && display_list\)[ \t]*$`, 1,
				"the menu drawn beside the list")
		},
		// The middle arm of a three-way chain: `if (got_int) ... else if
		// (menu) ... else if (list) ...`.  Dropping the arm has to drop its
		// `else` too.
		func() error {
			return c.sub(`^[ \t]*else if \(display_wildmenu && !display_list\)\n`+
				`[ \t]*\{\n[ \t]*win_redr_status_matches\([^\n]*\n[ \t]*\}\n`, "", 1,
				"the status-line menu arm of showmatches")
		},
		func() error {
			return c.sub(`^[ \t]*int         wim_noselect = p_wmnu[^\n]*\n`+
				`[ \t]*int         wim_noinsert = p_wmnu[^\n]*\n`, "", 1,
				"the two menu-only locals")
		},
		func() error {
			return c.sub(`if \(wim_noselect \|\| \(wim_list && !wim_full\)\)`,
				"if (wim_list && !wim_full)", 1, "the WILD_NOSELECT condition")
		},
		func() error {
			return c.dropIf(`^[ \t]*if \(wim_noinsert\)[ \t]*$`, 1, "the WILD_NOINSERT block")
		},
		func() error {
			return c.sub(`xp->xp_numfiles > \(\(wim_noselect \|\| wim_noinsert\) \? 0 : 1\)`,
				"xp->xp_numfiles > 1", 1, "the match-count threshold")
		},
		func() error {
			return c.sub(`^[ \t]*int show_menu = p_wmnu[^\n]*\n\n?`, "", 2,
				"the two `show_menu` locals")
		},
		func() error {
			return c.sub(`if \(wim_list \|\| show_menu\)`, "if (wim_list)", 2,
				"the two `wim_list || show_menu` conditions")
		},
		func() error {
			return c.sub(`if \(wim_list_next \|\| \(p_wmnu && \([^\n]*\)\)\)`,
				"if (wim_list_next)", 1, "the next-wildmode condition")
		},
		func() error {
			return c.sub(`if \(xpc\.xp_numfiles > 1 && \(\(!did_wild_list && \(wim_flags\[wim_index\] `+
				`& WIM_LIST\)\) \|\| p_wmnu\)\)`,
				"if (xpc.xp_numfiles > 1 && !did_wild_list && (wim_flags[wim_index] & WIM_LIST))",
				1, "the CTRL-L listing condition")
		},
		func() error {
			return c.sub(`^[ \t]*wildmenu_cleanup\([^;\n]*\);[ \t]*\n`, "", 4,
				"the wildmenu_cleanup calls")
		},
		func() error {
			return c.sub(`cmdline_pum_active\(\) \|\| wild_menu_showing \|\| did_wild_list`,
				"did_wild_list", 1, "the CTRL-E/CTRL-Y guard")
		},
		func() error {
			return c.sub(`msg_scrolled == 0 && wild_menu_showing == 0 && call_update_screen`,
				"msg_scrolled == 0 && call_update_screen", 1,
				"the redraw guard that asked whether the menu was up")
		},
		func() error {
			return c.sub(`^[ \t]*if \(pum_visible\(\)\)\n[ \t]*\{\n`+
				`[ \t]*cmdline_pum_display\(\);\n[ \t]*\}\n\n?`, "", 1,
				"the command-line popup redraw")
		},
		func() error {
			return c.sub(`^[ \t]*if \(cmdline_pum_active\(\)\)\n[ \t]*\{\n`+
				`[ \t]*cmdline_pum_remove\(&ccline, FALSE\);\n[ \t]*\}\n\n?`, "", 2,
				"the two popup removals in getcmdline_int")
		},
		func() error {
			return c.sub(`^[ \t]*if \(cmdline_match_array != NULL\)\n[ \t]*\{\n`+
				`[ \t]*cmdline_pum_remove\(get_cmdline_info\(\), FALSE\);\n[ \t]*\}\n\n?`, "", 1,
				"the popup removal in ExpandOne")
		},
		func() error {
			return c.sub(`^[ \t]*if \(cmdline_pum_active\(\)\)\n[ \t]*\{\n`+
				`[ \t]*cmdline_pum_cleanup\(&ccline\);\n[ \t]*\}\n\n?`, "", 1,
				"the CTRL-A popup cleanup")
		},
		func() error {
			return c.sub(`^[ \t]*end_wildmenu = end_wildmenu && \(!cmdline_pum_active\(\)[^\n]*\n`,
				"", 1, "the popup exception to leaving completion")
		},
		func() error {
			return c.dropIf(`^[ \t]*if \(cmdline_pum_active\(\)\)\n[ \t]*\{\n[ \t]*skip_pum_redraw`,
				1, "the popup teardown on any other key")
		},
		func() error {
			return c.sub(`^[ \t]*int     skip_pum_redraw = FALSE;\n\n?`, "", 1,
				"the popup redraw flag")
		},
		func() error {
			return c.dropIf(`^[ \t]*if \(c ==   \(-\(\(KS_EXTRA\) \+ \(\(int\)\(KE_WILD\) << 8\)\)\)   `+
				`&& firstc != .@.\)[ \t]*$`, 1, "the one place that set it")
		},
		func() error {
			return c.keepElse(`^[ \t]*if \(cmdline_pum_active\(\) && \(c == `,
				"the popup page-up/page-down arm")
		},
		// 'wildoptions' keeps its other three values and loses the one that
		// selected a menu that is no longer there.  An option value that is
		// still accepted and now does nothing is the thing Phase 3 exists to
		// prevent.
		func() error {
			return c.sub(`\{"fuzzy", "tagfile", "pum", "exacttext", NULL\}`,
				`{"fuzzy", "tagfile", "exacttext", NULL}`, 1,
				"the `pum` value of 'wildoptions'")
		},
	}
	for _, step := range steps {
		if err := step(); err != nil {
			return nil, err
		}
	}

	for _, l := range c.log {
		fmt.Fprintf(w, "  nowildmenu   %-3d %s\n", l.n, l.what)
	}
	left := 0
	for _, n := range []string{"p_wmnu", "wild_menu_showing", "cmdline_pum_active"} {
		left += bytes.Count(c.text, []byte(n))
	}
	fmt.Fprintf(w, "  nowildmenu   %d mentions left, all of them definitions for the sweep\n",
		left)
	return c.text, nil
}
