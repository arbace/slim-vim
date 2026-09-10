#!/usr/bin/env python3
"""Turn the EXCMD X-macro into two lists the compiler keeps aligned.

Usage:
    python3 tools/xmacro9.py <file>

`ex_cmds.h` is inlined twice on purpose, with EXCMD defined differently either
side of an `#undef`: once as `a`, which expands the list into `enum CMD_index`,
and once as a row of `cmdnames[]`.  That is the only construct in this file
where one name legitimately means two things, and it is why `#undef EXCMD` was
the one undef Phase 5 had to keep.

It also breaks a macro expander, silently and in a way that compiles most of
the way.  An expander builds one table keyed by name, so the second definition
overwrites the first and BOTH copies expand into rows -- leaving `enum
CMD_index` with 600 struct initialisers inside it and every `CMD_xxx` in the
file undeclared.  So the two definitions are given distinct names first, each
scoped to its own `#define`..`#undef` region, and the expander then treats them
as the two different macros they always were.

The second body is also rewritten, and this is a deliberate divergence from
upstream rather than a mechanical step:

    {(char_u *)b, ...}          ->   [a] = {(char_u *)b, ...}

A designated initialiser makes each row land at its own enumerator whatever
order the rows are written in.  The X-macro only guaranteed that the two
expansions had the same *order*, which is weaker: a dropped middle row shifts
every row after it and nothing says so.  With designators a dropped row leaves
a zeroed hole, which the 600-command sweep catches, and a dropped last row is
caught by the static_assert this adds.
"""

import re
import sys
from pathlib import Path

DEF = re.compile(r'^([ \t]*#[ \t]*define[ \t]+)EXCMD(\(.*)$')
UNDEF = re.compile(r'^[ \t]*#[ \t]*undef[ \t]+EXCMD\b')
USE = re.compile(r'\bEXCMD\b')

ROW_BODY = ('     [a] = {(char_u *)b, sizeof(b) - 1, c, (long_u)(d), e}')

ASSERT = '''
// Two lists, kept aligned by the compiler rather than by an X-macro: every row
// is written [CMD_append] = {...}, so it lands at its own enumerator whatever
// order the rows are in.  That is stronger than the macro's guarantee of equal
// *order*.  A dropped last row is caught here; a dropped middle row leaves a
// zeroed hole, which the 600-command sweep catches.
static_assert(sizeof(cmdnames) / sizeof(cmdnames[0]) == CMD_SIZE, "cmdnames[] and enum CMD_index have drifted apart");
'''


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    lines = path.read_text(errors='surrogateescape').split('\n')

    defs = [i for i, l in enumerate(lines) if DEF.match(l)]
    undefs = [i for i, l in enumerate(lines) if UNDEF.match(l)]
    if len(defs) != 2 or len(undefs) != 2:
        sys.exit('xmacro9: expected two #define EXCMD and two #undef EXCMD, '
                 'found %d and %d -- ex_cmds.h is meant to be inlined exactly '
                 'twice' % (len(defs), len(undefs)))

    names = ['EXCMD_ENUM', 'EXCMD_ROW']
    for k, (start, name) in enumerate(zip(defs, names)):
        end = min(u for u in undefs if u > start)
        for j in range(start, end):
            lines[j] = USE.sub(name, lines[j])
        if k == 1:
            m = DEF.match(lines[start].replace(name, 'EXCMD'))
            head = m.group(1) + name + '(a, b, c, d, e)'
            lines[start] = head + ROW_BODY

    # The undefs go with the ambiguity they were guarding.
    lines = [l for i, l in enumerate(lines) if i not in undefs]

    # The assert goes after the array the second list builds.
    text = '\n'.join(lines)
    m = re.search(r'\n\};\n(?=\s*\n?// -+ end ex_cmds\.h)', text)
    if not m:
        sys.exit('xmacro9: cannot find the end of cmdnames[] -- the assert has '
                 'nowhere to go, and an unanchored one is worse than none')
    text = text[:m.end()] + ASSERT + text[m.end():]

    path.write_text(text, errors='surrogateescape')
    print('  xmacro       EXCMD split by #undef region; rows are designated '
          'initialisers; static_assert added')


if __name__ == '__main__':
    main()
