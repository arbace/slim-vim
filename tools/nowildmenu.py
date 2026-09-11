#!/usr/bin/env python3
"""Remove the command-line completion menu, in both of its forms.

Usage:
    python3 tools/nowildmenu.py <file>

`'wildmenu'` draws the completion matches as a horizontal menu in the status
line and rebinds the arrow keys to walk it; `'wildoptions'=pum` draws the same
matches as a popup instead.  Both are a *display* of what Tab completion
already computed, and both cost a control path that reaches from the option
table through key translation into the redraw code.

Dropping the option is not enough, and that is the whole point of doing this by
hand rather than by sweep.  `p_wmnu` is read at thirteen places, and the
dead-code sweep cannot see that a variable which is never assigned TRUE makes a
branch unreachable -- it counts references, and every one of those thirteen is a
reference.  So `p_wmnu` is folded to FALSE *here*, at the source, and the sweep
is left the much easier question of what nothing mentions any more.

The popup form goes with it for the same reason in reverse: `cmdline_pum_*` is
reachable only through `'wildmenu'`, so with the option gone `cmdline_pum_active()`
can only ever answer FALSE -- while still being *called* ten times, which keeps
two hundred lines alive that can no longer run.  Fold those too.

What does NOT go: the popup menu itself.  `pum_display()` has a second caller in
insert-mode completion, so `popupmenu.c`'s machinery stays and only the
command line's use of it is cut.

THE DELTA: `'wildmenu'` and `'wildoptions'`'s `pum` value stop existing.  Tab
completion, `'wildmode'` and CTRL-D still list matches the way they do with
`set nowildmenu`, which is what this build now always is.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


class Cut:
    """Edits applied in order, each of which must find exactly what it expects.

    A miss is fatal rather than silent.  An edit that quietly matched nothing
    leaves the code it was meant to remove in place, and the report still says
    the phase succeeded -- which is how an inert option survives three passes.
    """

    def __init__(self, text):
        self.text = text
        self.log = []

    # -- primitives ---------------------------------------------------------

    def sub(self, pat, repl, count, what):
        self.text, n = re.subn(pat, repl, self.text, flags=re.M)
        if n != count:
            sys.exit('nowildmenu: %s -- expected %d, matched %d' % (what, count, n))
        self.log.append((what, n))

    def _block(self, pat):
        """(line_start, open_brace, close_brace) for the `if (...)` matching pat.

        The extent of the condition is found by matching parentheses, not by
        reading to the end of the line: these conditions are single-line by
        construction but full of parenthesised key codes, so a pattern that
        merely names the first term stops in the middle of one.
        """
        m = re.search(pat, self.text, re.M)
        if not m:
            return None
        blanked = cutil.blank(self.text)
        lp = self.text.index('(', m.start())
        rp = cutil.match(self.text, lp, blanked)
        if rp < 0:
            return None
        i = rp + 1
        while i < len(self.text) and self.text[i] in ' \t\n':
            i += 1
        if self.text[i] != '{':
            return None
        close = cutil.match(self.text, i, blanked)
        if close < 0:
            return None
        return m.start(), i, close

    def drop_if(self, pat, count, what):
        """Delete an `if (...)` and everything it guards."""
        for _ in range(count):
            found = self._block(pat)
            if not found:
                sys.exit('nowildmenu: %s -- no more blocks to drop' % what)
            start, _, close = found
            end = close + 1
            while end < len(self.text) and self.text[end] in ' \t':
                end += 1
            if end < len(self.text) and self.text[end] == '\n':
                end += 1
            if self.text[end:end + 1] == '\n':
                end += 1
            self.text = self.text[:start] + self.text[end:]
        if self._block(pat):
            sys.exit('nowildmenu: %s -- more blocks than expected' % what)
        self.log.append((what, count))

    def unwrap_if(self, pat, count, what):
        """Delete an `if (...)`'s header and braces, keeping its body."""
        for _ in range(count):
            found = self._block(pat)
            if not found:
                sys.exit('nowildmenu: %s -- no more blocks to unwrap' % what)
            start, opening, close = found
            body = self.text[self.text.index('\n', opening) + 1:
                             self.text.rfind('\n', 0, close) + 1]
            body = ''.join(l[4:] if l.startswith('    ') else l
                           for l in body.splitlines(keepends=True))
            end = close + 1
            while end < len(self.text) and self.text[end] in ' \t':
                end += 1
            if end < len(self.text) and self.text[end] == '\n':
                end += 1
            self.text = self.text[:start] + body + self.text[end:]
        self.log.append((what, count))

    def keep_else(self, pat, what):
        """`if (dead) { A } else { B }` becomes B."""
        found = self._block(pat)
        if not found:
            sys.exit('nowildmenu: %s -- not found' % what)
        start, _, close = found
        rest = self.text[close + 1:]
        m = re.match(r'[ \t]*\n[ \t]*else[ \t]*\n', rest)
        if not m:
            sys.exit('nowildmenu: %s -- no else branch, so there is nothing to '
                     'keep and deleting the if alone would delete the fallback'
                     % what)
        blanked = cutil.blank(self.text)
        opening = blanked.index('{', close + 1 + m.end())
        eclose = cutil.match(self.text, opening, blanked)
        body = self.text[self.text.index('\n', opening) + 1:
                         self.text.rfind('\n', 0, eclose) + 1]
        body = ''.join(l[4:] if l.startswith('    ') else l
                       for l in body.splitlines(keepends=True))
        end = eclose + 1
        while end < len(self.text) and self.text[end] in ' \t':
            end += 1
        if end < len(self.text) and self.text[end] == '\n':
            end += 1
        self.text = self.text[:start] + body + self.text[end:]
        self.log.append((what, 1))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    c = Cut(path.read_text(errors='surrogateescape'))

    # -- 1. the option itself, folded to FALSE at every read ----------------
    c.drop_if(r'^[ \t]*if \(p_wmnu\)[ \t]*$', 3, 'the three `if (p_wmnu)` blocks')
    c.unwrap_if(r'^[ \t]*if \(!p_wmnu \|\| \(c != ', 1,
                'the cmdline_leave guard that only wildmenu needed')

    # -- 2. showmatches() stops having a menu to draw -----------------------
    # Its second argument was "draw the wildmenu" and its fourth the wildmode
    # flags that only the menu read.  One substitution covers the definition,
    # the prototype and all six calls, because they have the same shape.
    c.sub(r'\bshowmatches\(([^,]+), [^,]+, ([^,]+), [^)]*\)',
          r'showmatches(\1, \2)', 7,
          'showmatches loses its wildmenu and wim_flags arguments')
    c.sub(r'^[ \t]*int         noselect = \(wim_flags_arg & WIM_NOSELECT\);\n'
          r'[ \t]*int         noinsert = \(wim_flags_arg & WIM_NOINSERT\);\n'
          r'[ \t]*int         cmdline_unchanged = noselect \|\| noinsert;\n', '', 1,
          'showmatches drops the three locals only the menu read')
    c.drop_if(r'^[ \t]*if \(display_wildmenu && !display_list && vim_strchr', 1,
              'the popup form of the wildmenu')
    c.drop_if(r'^[ \t]*if \(display_wildmenu && display_list\)[ \t]*$', 1,
              'the menu drawn beside the list')
    # The middle arm of a three-way chain: `if (got_int) ... else if (menu) ...
    # else if (list) ...`.  Dropping the arm has to drop its `else` too.
    c.sub(r'^[ \t]*else if \(display_wildmenu && !display_list\)\n'
          r'[ \t]*\{\n[ \t]*win_redr_status_matches\([^\n]*\n[ \t]*\}\n', '', 1,
          'the status-line menu arm of showmatches')

    # -- 3. cmdline_wildchar_complete: p_wmnu was two thirds of its logic ---
    c.sub(r'^[ \t]*int         wim_noselect = p_wmnu[^\n]*\n'
          r'[ \t]*int         wim_noinsert = p_wmnu[^\n]*\n', '', 1,
          'the two menu-only locals')
    c.sub(r'if \(wim_noselect \|\| \(wim_list && !wim_full\)\)',
          'if (wim_list && !wim_full)', 1, 'the WILD_NOSELECT condition')
    c.drop_if(r'^[ \t]*if \(wim_noinsert\)[ \t]*$', 1, 'the WILD_NOINSERT block')
    c.sub(r'xp->xp_numfiles > \(\(wim_noselect \|\| wim_noinsert\) \? 0 : 1\)',
          'xp->xp_numfiles > 1', 1, 'the match-count threshold')
    c.sub(r'^[ \t]*int show_menu = p_wmnu[^\n]*\n\n?', '', 2,
          'the two `show_menu` locals')
    c.sub(r'if \(wim_list \|\| show_menu\)', 'if (wim_list)', 2,
          'the two `wim_list || show_menu` conditions')
    c.sub(r'if \(wim_list_next \|\| \(p_wmnu && \([^\n]*\)\)\)',
          'if (wim_list_next)', 1, 'the next-wildmode condition')

    # -- 4. the two remaining reads in getcmdline_int -----------------------
    c.sub(r'if \(xpc\.xp_numfiles > 1 && \(\(!did_wild_list && \(wim_flags\[wim_index\] '
          r'& WIM_LIST\)\) \|\| p_wmnu\)\)',
          'if (xpc.xp_numfiles > 1 && !did_wild_list && (wim_flags[wim_index] & WIM_LIST))',
          1, 'the CTRL-L listing condition')
    c.sub(r'^[ \t]*wildmenu_cleanup\([^;\n]*\);[ \t]*\n', '', 4,
          'the wildmenu_cleanup calls')
    c.sub(r'cmdline_pum_active\(\) \|\| wild_menu_showing \|\| did_wild_list',
          'did_wild_list', 1, 'the CTRL-E/CTRL-Y guard')
    c.sub(r'msg_scrolled == 0 && wild_menu_showing == 0 && call_update_screen',
          'msg_scrolled == 0 && call_update_screen', 1,
          'the redraw guard that asked whether the menu was up')

    # -- 5. the popup form: reachable only through the option just removed --
    c.sub(r'^[ \t]*if \(pum_visible\(\)\)\n[ \t]*\{\n'
          r'[ \t]*cmdline_pum_display\(\);\n[ \t]*\}\n\n?', '', 1,
          'the command-line popup redraw')
    c.sub(r'^[ \t]*if \(cmdline_pum_active\(\)\)\n[ \t]*\{\n'
          r'[ \t]*cmdline_pum_remove\(&ccline, FALSE\);\n[ \t]*\}\n\n?', '', 2,
          'the two popup removals in getcmdline_int')
    c.sub(r'^[ \t]*if \(cmdline_match_array != NULL\)\n[ \t]*\{\n'
          r'[ \t]*cmdline_pum_remove\(get_cmdline_info\(\), FALSE\);\n[ \t]*\}\n\n?', '', 1,
          'the popup removal in ExpandOne')
    c.sub(r'^[ \t]*if \(cmdline_pum_active\(\)\)\n[ \t]*\{\n'
          r'[ \t]*cmdline_pum_cleanup\(&ccline\);\n[ \t]*\}\n\n?', '', 1,
          'the CTRL-A popup cleanup')
    c.sub(r'^[ \t]*end_wildmenu = end_wildmenu && \(!cmdline_pum_active\(\)[^\n]*\n', '', 1,
          'the popup exception to leaving completion')
    c.drop_if(r'^[ \t]*if \(cmdline_pum_active\(\)\)\n[ \t]*\{\n[ \t]*skip_pum_redraw', 1,
              'the popup teardown on any other key')
    c.sub(r'^[ \t]*int     skip_pum_redraw = FALSE;\n\n?', '', 1,
          'the popup redraw flag')
    c.drop_if(r'^[ \t]*if \(c ==   \(-\(\(KS_EXTRA\) \+ \(\(int\)\(KE_WILD\) << 8\)\)\)   '
              r'&& firstc != .@.\)[ \t]*$', 1,
              'the one place that set it')
    c.keep_else(r'^[ \t]*if \(cmdline_pum_active\(\) && \(c == ',
                'the popup page-up/page-down arm')

    # `'wildoptions'` keeps its other three values and loses the one that
    # selected a menu that is no longer there.  An option value that is still
    # accepted and now does nothing is the thing Phase 5 exists to prevent.
    c.sub(r'\{"fuzzy", "tagfile", "pum", "exacttext", NULL\}',
          '{"fuzzy", "tagfile", "exacttext", NULL}', 1,
          "the `pum` value of 'wildoptions'")

    path.write_text(c.text, errors='surrogateescape')
    for what, n in c.log:
        print('  nowildmenu   %-3d %s' % (n, what))
    left = sum(c.text.count(n) for n in
               ('p_wmnu', 'wild_menu_showing', 'cmdline_pum_active'))
    print('  nowildmenu   %d mentions left, all of them definitions for the sweep'
          % left)


if __name__ == '__main__':
    main()
