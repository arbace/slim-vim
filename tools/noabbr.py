#!/usr/bin/env python3
"""No abbreviations: nothing can define one, so nothing asks whether one applies.

Usage:
    python3 tools/noabbr.py <file>

tools/retire.py points the twelve rows -- :abbreviate, :noreabbrev,
:unabbreviate, :abclear and their `i` and `c` forms -- at ex_ni, and with them
goes the only way an abbreviation is ever defined.  What is left is the
question: insert mode asks `echeck_abbr()` on ESC, CTRL-O, CTRL-L, Tab, Enter
and every non-word character, and the command line asks `ccheck_abbr()` twice.
With no abbreviation there to find, each asks it for ever and is told no.  So
the questions go, and the sweep takes check_abbr() -- 195 lines -- with the two
wrappers and the handlers.

Each cut folds a test whose answer is now known:

  * `if (echeck_abbr(...)) { ... }`  and  `if (ccheck_abbr(...)) { ... }`
    guard what happens when an abbreviation fired, so the block goes.
  * `!echeck_abbr(x) && c != Ctrl_RSB` is `c != Ctrl_RSB`.
  * `(ccheck_abbr(x) || c == Ctrl_RSB)` is `c == Ctrl_RSB` -- CTRL-] on the
    command line still triggers "an abbreviation", which is to say nothing, and
    still does not insert itself.

What stays: the mapping code's `abbr` parameters and list, which mappings share.
Nothing can put an entry on the abbreviation list any more, and nothing here
pretends that makes the shared code smaller.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

FOLDS = [
    ('insert mode: ESC expanding an abbreviation first', r'^[ \t]*if \(echeck_abbr\(ESC \+ ABBR_OFF\)\)$'),
    ('insert mode: CTRL-O expanding an abbreviation first', r'^[ \t]*if \(echeck_abbr\(Ctrl_O \+ ABBR_OFF\)\)$'),
    ("insert mode: CTRL-L under 'insertmode'", r'^[ \t]*if \(echeck_abbr\(Ctrl_L \+ ABBR_OFF\)\)$'),
    ('insert mode: Tab expanding an abbreviation first', r'^[ \t]*if \(echeck_abbr\(TAB \+ ABBR_OFF\)\)$'),
    ('insert mode: Enter expanding an abbreviation first', r'^[ \t]*if \(echeck_abbr\(c \+ ABBR_OFF\)\)$'),
    ('the command line: a special key expanding an abbreviation', r'^[ \t]*if \(ccheck_abbr\(c \+ ABBR_OFF\)\)$'),
]

LITERAL = [
    ('insert mode: a non-word character inserting unless an abbreviation took it',
     'if (vim_iswordc(c) || (!echeck_abbr((has_mbyte && c >= 0x100) ? (c + ABBR_OFF) : c) && c != Ctrl_RSB))',
     'if (vim_iswordc(c) || c != Ctrl_RSB)'),
    ('the command line: a non-word character expanding an abbreviation',
     '(ccheck_abbr((has_mbyte && c >= 0x100) ? (c + ABBR_OFF) : c) || c == Ctrl_RSB)',
     'c == Ctrl_RSB'),
]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    for what, pattern in FOLDS:
        try:
            text = cutil.fold_never(text, pattern, 1, re.M)
        except ValueError as e:
            sys.exit('noabbr: %s -- %s' % (what, e))
        print('  noabbr       %s' % what)
    for what, old, new in LITERAL:
        n = text.count(old)
        if n != 1:
            sys.exit('noabbr: %s -- occurs %d times, not once' % (what, n))
        text = text.replace(old, new)
        print('  noabbr       %s' % what)

    # Nothing may still ASK.  The wrappers must have no caller at all, and
    # check_abbr() no caller outside the two wrappers -- which the sweep takes,
    # so a call left inside one of them is not a caller.
    spans = [cutil.find_definition(text, n) for n in ('echeck_abbr', 'ccheck_abbr', 'check_abbr')]
    inside = lambda pos: any(s and s[0] <= pos < s[1] for s in spans)
    calls = [m for m in re.finditer(r'\b[ec]?check_abbr\(', text)
             if not inside(m.start())
             and not re.match(r'static\s+int\s+[ec]?check_abbr\(', text[text.rfind('\n', 0, m.start()) + 1:])]
    if calls:
        sys.exit('noabbr: still asked at:\n    ' + '\n    '.join(
            text[text.rfind('\n', 0, m.start()) + 1:text.find('\n', m.start())].strip()[:100] for m in calls))

    path.write_text(text, errors='surrogateescape')
    print('  noabbr       nothing asks whether an abbreviation applies')


if __name__ == '__main__':
    main()
