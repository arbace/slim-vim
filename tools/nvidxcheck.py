#!/usr/bin/env python3
"""nv_cmd_idx[] still indexes nv_cmds[] -- one entry per row, each row once.

Usage:
    python3 tools/nvidxcheck.py <file>

Normal mode finds a key's handler through `nv_cmd_idx[]`, a sorted index into
`nv_cmds[]` that upstream generates and this tree writes into the C as a
constant.  Nothing recomputes it, and the compiler cannot see that it is wrong:
delete a row from `nv_cmds[]` and the index still compiles, still has its old
length, and still points at row numbers that now belong to other keys.

The mouse phase did exactly that -- 22 rows deleted -- and normal-mode arrows
stopped working for twelve phases, because every harness that typed an arrow
typed it in insert mode, which decodes keys in a switch.

So this asks the one thing a deletion always breaks: the index must be a
permutation of 0..len(nv_cmds)-1.  It does not check the sort order, which would
mean evaluating each row's key expression; a table whose rows are only ever
pointed at `nv_error` never needs it.
"""

import re
import sys


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    t = open(sys.argv[1], encoding='utf-8', errors='surrogateescape').read()
    try:
        a = t.index('} nv_cmds[] =')
        i = t.index('nv_cmd_idx[] =')
    except ValueError:
        sys.exit('  nvidx        nv_cmds[] or nv_cmd_idx[] is not where this expects')
    table = t[a:t.index('\n};', a)]
    rows = len(re.findall(r'^[ \t]*\{[^\n]*\}[ \t]*,?[ \t]*$', table, re.M))
    idx = [int(x) for x in re.findall(r'^[ \t]*(\d+),?[ \t]*$', t[i:t.index('\n};', i)], re.M)]
    if sorted(idx) != list(range(rows)):
        print('  nvidx        nv_cmd_idx[] has %d entries for %d rows of nv_cmds[] -- '
              'a row was deleted, and every key past it resolves to the wrong one' % (len(idx), rows))
        return 1
    print('  nvidx        nv_cmd_idx[] indexes each of the %d rows of nv_cmds[] once' % rows)
    return 0


if __name__ == '__main__':
    sys.exit(main())
