#!/usr/bin/env python3
"""Rename an identifier inside one former file's region of the merged vim.c.

Usage:
    python3 tools/renameregion.py <renames.txt> <vim.c>

Applies every entry whose scope is `vim.c@<banner>` -- a rename that is only
correct within the part of the merged file that came from one former source.

The one in force is the regexp opcode `WHITE`, which shadows the colour enum's
`WHITE`.  As a macro that is legal, so nothing complains until Phase 9 turns it
into an enumerator; renaming it here, where the banners still say which code is
which, is what makes the rename possible at all.  A file-wide substitution
would rename the colour too, and the build would be perfectly happy about it.

The region runs from its banner to the next banner of any kind.
"""

import re
import sys
from pathlib import Path

BANNER = re.compile(r'^// (=+|-+) ')


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    table, target = Path(sys.argv[1]), Path(sys.argv[2])

    entries = []
    for line in table.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        scope, old, new = line.split(':')
        if '@' in scope:
            file_part, region = scope.split('@')
            if file_part == target.name:
                entries.append((region, old, new))
    if not entries:
        return

    lines = target.read_text(errors='surrogateescape').split('\n')

    # Where each banner region starts and ends.
    marks = [i for i, l in enumerate(lines) if BANNER.match(l)]
    total = 0
    for region, old, new in entries:
        start = end = None
        for k, i in enumerate(marks):
            if region in lines[i]:
                start = i
                end = marks[k + 1] if k + 1 < len(marks) else len(lines)
                break
        if start is None:
            sys.exit('renameregion: no banner for %s in %s' % (region, target))
        pat = re.compile(r'\b%s\b' % re.escape(old))
        n = 0
        for j in range(start, end):
            lines[j], k = pat.subn(new, lines[j])
            n += k
        total += n
        print('  rename       %s -> %s, %d occurrences inside %s'
              % (old, new, n, region))

    target.write_text('\n'.join(lines), errors='surrogateescape')


if __name__ == '__main__':
    main()
