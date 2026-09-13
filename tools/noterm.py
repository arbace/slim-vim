#!/usr/bin/env python3
"""The terminal is what the build says, not what the environment claims.

Usage:
    python3 tools/noterm.py <file>

Five environment variables describe the terminal, and the editor believes all
of them: `$TERM` picks a capability table, `$LINES` and `$COLUMNS` override the
size the kernel reports, `$COLORS` overrides the colour count the table gives,
and `$COLORFGBG` is read for the background.

**The compiled name is `xterm-256color`, not `xterm`, and that choice is the
whole care in this phase.** Measured on the shipped binary first:

    TERM=xterm-256color   -> term=xterm-256color  t_Co=256
    TERM=xterm            -> term=xterm           t_Co=8
    TERM= (unset)         -> term=xterm           t_Co=8

`set_termname()` keeps the requested name in `requested` and tests
`strstr(requested, "256color")` to apply `builtin_256colors` on top of the
table it chose.  So the obvious fallback -- the one the unset case already took
-- would have cost eight of every nine colours the terminal can show, silently,
for nothing.  `xterm-256color` resolves to the same `builtin_xterm` table and
keeps the add-on.

`-T <term>` STAYS.  It is not the environment, and with one compiled default it
is the only way left to say "this is a dumb terminal".  The ten built-in entries
are still there and `-T` still reaches them.

The size falls back to nothing: `ioctl(TIOCGWINSZ)` answers or the compiled
default does.  An editor that believes `$LINES` over the kernel is an editor
that draws off the bottom of a resized window.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

EDITS = [
    ("$TERM choosing the capability table",
     r'[ \t]*if \(term == NULL\)\n[ \t]*\{\n'
     r'[ \t]*term =  \(char_u \*\)getenv\(\(char \*\)\(\(char_u \*\)"TERM"\)\) ;\n[ \t]*\}\n', ''),
    ("the fallback, which becomes the only path and must keep the colours",
     r'([ \t]*if \(term == NULL \|\| \*term == NUL\)\n[ \t]*\{\n[ \t]*term =  \(char_u \*\))'
     r'"xterm" ;\n', r'\1"xterm-256color" ;\n'),
    ("$COLORS overriding the table's colour count",
     r'[ \t]*\{\n[ \t]*env_colors =  \(char_u \*\)getenv\(\(char \*\)\(\(char_u \*\)"COLORS"\)\) ;\n'
     r'(?:[^\n]*\n)*?^[ \t]{4}\}\n', ''),
    ("$COLORS suppressing the 256-colour probe response",
     r'[ \t]*if \( \(char_u \*\)getenv\(\(char \*\)\(\(char_u \*\)"COLORS"\)\)  == NULL\)\n'
     r'[ \t]*\{\n([ \t]*may_adjust_color_count\(256\);\n)[ \t]*\}\n', r'\1'),
]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')
    # Brace-matched, not regex-matched: this block contains two inner `if`s
    # and a lazy pattern stops at the first of their closing braces.
    text = cutil.drop_if(
        text, r'^[ \t]*if \(columns == 0 \|\| rows == 0 \|\| '
              r'vim_strchr\(p_cpo, CPO_TSIZE\) != NULL\)$', flags=re.M)
    print('  noterm       $LINES and $COLUMNS overriding the kernel')

    for what, pat, repl in EDITS:
        text, n = re.subn(pat, repl, text, count=1, flags=re.M)
        if n != 1:
            sys.exit('noterm: %s -- not found' % what)
        print('  noterm       %s' % what)
    # Only a getenv counts.  "TERM" is also a highlight-group key -- `:hi
    # term=bold` -- and the name of SIGTERM in the signal table, and a bare
    # substring test flags both.
    for bad in ('TERM', 'LINES', 'COLUMNS', 'COLORS'):
        if re.search(r'getenv\([^)]*"%s"' % bad, text):
            sys.exit('noterm: something still calls getenv("%s")' % bad)
    path.write_text(text, errors='surrogateescape')
    print('  noterm       the terminal is xterm-256color by construction')


if __name__ == '__main__':
    main()
