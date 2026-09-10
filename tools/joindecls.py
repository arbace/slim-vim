#!/usr/bin/env python3
"""Join the two-line EXTERN/INIT declarations onto one line.

Usage:
    python3 tools/joindecls.py <file>

They are written

    EXTERN char_u e_internal_error_lalloc_zero[]
            INIT(= "E341: Internal error: lalloc(0, )");

with balanced parentheses on both lines, so the pass that joins parenthesised
groups had no reason to touch them.  What makes them worth joining is what
comes next: the dead-code sweep deletes by line, and "delete the line" on a
declaration like this leaves half of it behind -- after which the failure
surfaces as an unrelated undeclared symbol somewhere else entirely.

**Join the two-line form only.**  Four are written across three lines, with the
initialiser and the `;` each on their own -- Rows, saved_cursor, typebuf and
last_cursormoved -- and the reference tree keeps them that way.  A joiner that
runs "until the line ends in a semicolon" swallows those four as well and
produces four lines of difference for nothing.  The test used here is exact:
the next line must be an INIT that ends the declaration.
"""

import re
import sys
from pathlib import Path

HEAD = re.compile(r'^EXTERN\b')
TAIL = re.compile(r'^\s+INIT.*;\s*$')


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    lines = path.read_text(errors='surrogateescape').split('\n')

    out = []
    i = joined = 0
    while i < len(lines):
        line = lines[i]
        if (HEAD.match(line) and not line.rstrip().endswith(';')
                and i + 1 < len(lines) and TAIL.match(lines[i + 1])):
            out.append(line.rstrip() + ' ' + lines[i + 1].strip())
            joined += 1
            i += 2
            continue
        out.append(line)
        i += 1

    path.write_text('\n'.join(out), errors='surrogateescape')
    print('  joindecls    %d two-line declarations joined' % joined)


if __name__ == '__main__':
    main()
