#!/usr/bin/env python3
"""Point Ex command rows at `ex_ni`, so the name still parses and does nothing.

Usage:
    python3 tools/retire.py <file> <command> ...

PURE-GOAL.md rule 3: **a command is never deleted from the table.**
`enum CMD_index`, `cmdnames[]` and the derived `ex_cmdidxs` block keep their
shape, nothing renumbers, and the trap `SLIM-GOAL.md` records cannot fire --
delete only `CMD_help` and `:help` silently starts running `:helpclose`, because
a removed name is inherited by the next command sharing its prefix.

It also happens to be the honest answer.  An editor with no filesystem to change
into should say `:cd` is not implemented, not pretend the name was never a
command.

Three phases wrote this loop out by hand before it was worth extracting; the
rule each of them got right and that a fourth would eventually get wrong is that
**a row is matched by its string literal, not by its enumerator.** The two
disagree more often than they look: `[CMD_bprevious]` is spelled `"bNext"`, and
several handlers serve rows whose enumerator name shares nothing with the
command.

A name it cannot find is fatal.  A silent miss leaves the command working and
the report still says the phase succeeded, which is exactly how an inert
feature survives three passes.
"""

import re
import sys
from pathlib import Path

ROW = r'(\[CMD_\w+\] = \{\(char_u \*\)"%s", sizeof\("%s"\) - 1, )(\w+)'


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    names = sys.argv[2:]
    text = path.read_text(errors='surrogateescape')

    done, already = [], []
    for name in names:
        pat = re.compile(ROW % (re.escape(name), re.escape(name)))
        m = pat.search(text)
        if not m:
            sys.exit('retire: no row for :%s -- the table has moved, and a '
                     'phase that retires nothing still reports success' % name)
        if m.group(2) == 'ex_ni':
            already.append(name)
            continue
        text, k = pat.subn(lambda m: m.group(1) + 'ex_ni', text)
        if k != 1:
            sys.exit('retire: %d rows for :%s, expected one' % (k, name))
        done.append(name)

    path.write_text(text, errors='surrogateescape')
    print('  retire       %d commands now answer "not implemented": %s'
          % (len(done), ' '.join(done)))
    if already:
        print('  retire       %d were already inert: %s'
              % (len(already), ' '.join(already)))


if __name__ == '__main__':
    main()
