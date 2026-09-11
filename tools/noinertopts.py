#!/usr/bin/env python3
"""The last readers of six options that no longer decide anything.

Usage:
    python3 tools/noinertopts.py <file>

Six options have been inert since the phase that removed what they controlled --
'path' and 'suffixesadd' since the file finder went, 'tags' and 'tagcase' since
the tag stack, 'autoread' since the timestamp poll, 'swapfile' since the swap
file -- and all six are still there, because a row is what initialises its
global and tools/dropoptions.py refuses to leave one dangling.

Most of what keeps them is plumbing, which tools/droplocal.py removes.  Three
are not plumbing, and each has to be looked at:

  * ex_drop() set 'autoread' on, checked the timestamp, and set it back.  Phase
    17 took the check out from between, so what is left is a variable saved and
    restored across nothing at all -- a block that was already a no-op before
    this phase arrived to delete it.
  * do_set_option_bool() special-cases `:setlocal autoread` to mean "follow the
    global", which is the -1 sentinel.  With no option there is nothing to
    follow.
  * ml_open() asks whether this buffer may have a swap file.  Since Phase 15 the
    answer has been no whatever 'swapfile' said, so it now says no directly.

The ORDER matters and is the reason this is a phase rather than a call.  The
option callbacks -- did_set_tagcase(), did_set_swapfile() -- read the buffer
field too, and they are reachable only from the row.  So the rows go first, the
sweep takes the callbacks, and only then can the field go: remove the field
first and the file stops compiling, which stops the sweep, which is what would
have removed the callbacks.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

EDITS = [
    ("ex_drop saving and restoring 'autoread' across nothing",
     r'[ \t]*if \(!bufIsChanged\(curbuf\)\)\n[ \t]*\{\n'
     r'[ \t]*int save_ar = curbuf->b_p_ar;\n\n'
     r'[ \t]*curbuf->b_p_ar = TRUE;\n'
     r'[ \t]*curbuf->b_p_ar = save_ar;\n[ \t]*\}\n', ''),
    ("`:setlocal autoread` meaning \"follow the global\"",
     r'[ \t]*if \(\(int \*\)varp == &curbuf->b_p_ar && opt_flags == OPT_LOCAL\)\n'
     r'[ \t]*\{\n[ \t]*value = -1;\n[ \t]*\}\n[ \t]*else if',
     '        if'),
    # THE ONE THAT SEGFAULTED.  Every other reader of these six globals is an
    # ADDRESS comparison -- `var == &p_path` -- which survives the global going
    # NULL without noticing.  This one DEREFERENCES p_tc, at startup, in a
    # function that runs before anything else, so the editor died before its
    # first keystroke and the harness reported it as all 67 behaviour cases,
    # the terminal table and every Ex command moving at once.  That is the
    # second time this session a dropped option has looked exactly like that.
    # Three address comparisons that can no longer be true.  They are harmless
    # at run time -- an address test against a variable nobody can name is
    # simply false -- but they keep the globals alive, and a global that is
    # alive is one the phase's own check cannot prove is unread.
    ("option_expand escaping for 'path' and 'tags'",
     r'[ \t]*int esc = var == &p_tags \|\| var == &p_path;\n', '    int esc = FALSE;\n'),
    # Two sibling blocks, one for directories and one for files, each asking
    # whether the option being completed is one of these three.  Both collapse
    # to the else arm -- and the replacement carries the indentation, because
    # `\1` would keep the inner line's, which is one level too deep once the
    # block around it is gone.
    ("the directory-completion backslash rule for 'path'",
     r'[ \t]*if \(p == \(char_u \*\)&p_path \|\| p == \(char_u \*\)&p_cdpath\)\n'
     r'[ \t]*\{\n[ \t]*xp->xp_backslash = XP_BS_THREE;\n[ \t]*\}\n'
     r'[ \t]*else\n[ \t]*\{\n[ \t]*xp->xp_backslash = XP_BS_ONE;\n[ \t]*\}\n',
     '            xp->xp_backslash = XP_BS_ONE;\n'),
    # And one term of a longer disjunction, where the other options named are
    # all still real.  Only the term goes.
    ("'path' as a directory-completion context",
     r' \|\| p == \(char_u \*\)&p_path', ''),
    ("the file-completion backslash rule for 'tags'",
     r'[ \t]*if \(p == \(char_u \*\)&p_tags\)\n'
     r'[ \t]*\{\n[ \t]*xp->xp_backslash = XP_BS_THREE;\n[ \t]*\}\n'
     r'[ \t]*else\n[ \t]*\{\n[ \t]*xp->xp_backslash = XP_BS_ONE;\n[ \t]*\}\n',
     '            xp->xp_backslash = XP_BS_ONE;\n'),
    ("didset_string_options reading 'tagcase' at startup",
     r'[ \t]*\(void\)opt_strings_flags\(p_tc, p_tc_values, &tc_flags, FALSE\);\n', ''),
    ("ml_open asking whether this buffer may have a swap file",
     r'[ \t]*if \(p_uc && buf->b_p_swf\)\n[ \t]*\{\n'
     r'[ \t]*buf->b_may_swap = true;\n[ \t]*\}\n'
     r'[ \t]*else\n[ \t]*\{\n[ \t]*buf->b_may_swap = false;\n[ \t]*\}\n',
     '    buf->b_may_swap = false;\n'),
]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    for what, pat, repl in EDITS:
        text, n = re.subn(pat, repl, text, flags=re.M)
        if n != 1:
            sys.exit('noinertopts: %s -- expected 1, matched %d' % (what, n))
        print('  noinertopts  %s' % what)

    path.write_text(text, errors='surrogateescape')


if __name__ == '__main__':
    main()
