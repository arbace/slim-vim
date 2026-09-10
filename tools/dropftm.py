#!/usr/bin/env python3
"""Delete the feature-test macros, and the blank they leave behind.

Usage:
    python3 tools/dropftm.py <file>

_XOPEN_SOURCE, _BSD_SOURCE, _SVID_SOURCE, _DEFAULT_SOURCE and _REENTRANT are
glibc-era.  musl declares everything unconditionally, so deleting them leaves
the preprocessed output byte-identical -- which is the check the caller runs.
(If this is ever built against another libc, they are the first thing to put
back, above the first #include.  _XOPEN_SOURCE 700 was upstream's, for
strptime() and mkdtemp(); the other three were for nanosecond timestamps in
struct stat.)

Deleting a line that sat between two blank lines leaves two blank lines where
there was one, and this file's paragraphing is a property nobody else is
checking -- neither verification tier can see a blank line.  So the blank goes
with the line, and only there: a general collapse of blank runs would take nine
others elsewhere in the file that belong exactly where they are.
"""

import re
import sys
from pathlib import Path

FTM = re.compile(r'^[ \t]*#[ \t]*define[ \t]+'
                 r'_(XOPEN_SOURCE|BSD_SOURCE|SVID_SOURCE|DEFAULT_SOURCE|REENTRANT)\b')


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    lines = path.read_text(errors='surrogateescape').split('\n')

    out = []
    i = 0
    dropped = blanks = 0
    while i < len(lines):
        if FTM.match(lines[i]):
            dropped += 1
            if (out and out[-1].strip() == ''
                    and i + 1 < len(lines) and lines[i + 1].strip() == ''):
                i += 2
                blanks += 1
                continue
            i += 1
            continue
        out.append(lines[i])
        i += 1

    path.write_text('\n'.join(out), errors='surrogateescape')
    print('  feature      %d test macros deleted, %d blank lines with them'
          % (dropped, blanks))


if __name__ == '__main__':
    main()
