#!/usr/bin/env python3
"""Say `static` on every definition, so linkage stops depending on order.

Usage:
    python3 tools/allstatic.py <file> [--delete]

1,473 function definitions in this file do not say `static` and are static
anyway, because a declaration earlier in the file said it for them and a
definition that follows one inherits its internal linkage.  That works, and it
is a trap with a long fuse: delete the declaration -- for being redundant, for
tidiness, by accident -- and the function quietly acquires external linkage.
Nothing fails.  The build is clean, the editor runs, and `nm` grows a symbol
that this tree's central claim says cannot exist.

Phase 7 met that trap and worked around it, handing `static` to each definition
whose declaration it removed.  This finishes the job from the other end: every
definition says what its linkage is, and no declaration anywhere is load-bearing
for anything but order.  After it, a prototype can be removed for being
unnecessary without anyone having to think about linkage at all.

`main` is the exception and the only one -- it is the program's entry point and
the one symbol that is meant to be external.  The caller's `nm` check is what
proves that is still true.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil
import funcreach

LEADING = re.compile(r'[ \t]*')


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    delete = '--delete' in sys.argv
    if not args:
        sys.exit(__doc__)
    path = Path(args[0])
    text = path.read_text(errors='surrogateescape')
    blanked = cutil.blank(text)

    defs = funcreach.definitions(text, blanked)
    if len(defs) < 100:
        sys.exit('allstatic: only %d definitions found; the shape has moved '
                 'and acting on that would be reckless' % len(defs))

    todo = []
    for name, (start, _) in defs.items():
        if name == 'main':
            continue
        line_end = text.index('\n', start)
        line = text[start:line_end]
        if re.match(r'[ \t]*static\b', line):
            continue
        todo.append((start + len(LEADING.match(line).group(0)), name))

    print('  allstatic    %d definitions, %d already static, %d to say so'
          % (len(defs), len(defs) - len(todo) - 1, len(todo)))

    if not (todo and delete):
        return

    for at, _ in sorted(todo, reverse=True):
        text = text[:at] + 'static ' + text[at:]
    path.write_text(text, errors='surrogateescape')
    print('  allstatic    linkage is now a property of each definition, not of '
          'the file\'s order')


if __name__ == '__main__':
    main()
