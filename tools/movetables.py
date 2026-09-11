#!/usr/bin/env python3
"""Move a file-scope table below the functions it names.

Usage:
    python3 tools/movetables.py <file> <table> ...

`cmdnames[]` names six hundred Ex command handlers and sits near the top of the
file, so every one of them needs a forward declaration -- not because anything
calls them early, but because a table mentions them early.  Three tables
account for 331 of the 2,045 declarations left in this file: `options[]` (159),
`cmdnames[]` (102) and `nv_cmds[]` (70).

Moving the table below its handlers removes all of those, and costs one
declaration of the table itself.  That is the whole trade: six hundred
declarations for one.

It is also the only lever here worth pulling.  The alternative -- reordering
functions into topological order -- fails on both counts: 1,335 of the 3,234
functions are in a single mutually recursive component that no ordering can
untangle, and sorting the rest would destroy the banner structure that is the
only navigation a 165,000-line file has.

Three things this has to get right:

  * **The struct definition stays put.** These tables are written
    `static struct cmdname { ... } cmdnames[] = {...};` -- a type definition and
    an object in one.  Moving both would leave the declaration left behind
    naming an incomplete type.  The type stays where it was; only the array
    travels.
  * **Anything following the table that depends on it travels too** -- the
    `static_assert` on `sizeof(cmdnames)` is part of the table, not of what
    comes after it.
  * **The destination is computed**, as the end of the last function the table
    names.  Putting it "at the end of the file" would work and would also put
    it after `main`, which this tree ends with deliberately.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil
import funcreach

IDENT = re.compile(r'\b[A-Za-z_]\w*\b')


def find_table(text, blanked, name):
    """(decl_start, body_start, end, header, tag) for `NAME[] = {...};`."""
    m = re.search(r'^(static[ \t]+(?:const[ \t]+)?struct[ \t]+(\w+)\b)'
                  r'((?:[ \t]*\n\{(?:[^{}]|\n)*?\n\})?)[ \t]*\n?[ \t]*%s\[\][ \t]*=[ \t]*$'
                  % re.escape(name), blanked, re.M)
    if not m:
        return None
    open_brace = blanked.index('{', m.end())
    close = cutil.match(text, open_brace, blanked)
    if close < 0:
        return None
    end = close + 1
    while end < len(text) and text[end] in ' \t':
        end += 1
    if text[end] == ';':
        end += 1
    return m.start(), m.end(), end, m.group(1), m.group(2), m.group(3)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    tables = sys.argv[2:]
    text = path.read_text(errors='surrogateescape')

    moved = []
    for name in tables:
        blanked = cutil.blank(text)
        defs = funcreach.definitions(text, blanked)
        found = find_table(text, blanked, name)
        if not found:
            sys.exit('movetables: no file-scope table %s[] = {...} here' % name)
        decl_start, head_end, end, header, tag, sbody = found

        # Everything the table names that is a function defined here.
        body = text[decl_start:end]
        named = set(IDENT.findall(body)) & set(defs)
        if not named:
            print('  movetables   %s names no function; leaving it alone' % name)
            continue
        target = max(defs[n][1] for n in named)
        if target < decl_start:
            print('  movetables   %s already follows everything it names' % name)
            continue

        # The table travels with whatever immediately follows and depends on
        # it -- the static_assert over sizeof() is part of this table.
        tail = end
        rest = text[end:end + 600]
        m = re.match(r'\n+(//[^\n]*\n)*static_assert\([^;]*%s[^;]*;' % re.escape(name),
                     rest)
        if m:
            tail = end + m.end()

        block = (header + ' ' + name + '[] =' +
                 text[head_end:tail]) if sbody.strip() else text[decl_start:tail]
        # Where it lands: just after that function's closing brace.
        # What stays behind: a tentative definition, so the earlier users of
        # the table still have a name to refer to.
        # The TYPE stays where it was.  These tables are written
        # `static struct cmdname { ... } cmdnames[] = {...};` -- a type
        # definition and an object in one -- and moving both would leave the
        # declaration behind naming an incomplete type, which is an error at
        # the first `sizeof` and a confusing one.
        stub = ''
        if sbody.strip():
            stub += 'struct %s%s;\n\n' % (tag, sbody)
        stub += '%s %s[];\n' % (header, name)

        # Cut first, then find the destination again: every offset after the
        # cut has moved, and recomputing is cheaper than reasoning about it.
        text = text[:decl_start] + stub + text[tail:]
        blanked2 = cutil.blank(text)
        defs2 = funcreach.definitions(text, blanked2)
        target2 = max(defs2[n][1] for n in named if n in defs2)
        at = text.index('\n', target2) + 1
        text = text[:at] + '\n' + block.strip('\n') + '\n' + text[at:]
        moved.append((name, len(named)))

    path.write_text(text, errors='surrogateescape')
    for name, n in moved:
        print('  movetables   %s moved below the %d functions it names' % (name, n))


if __name__ == '__main__':
    main()
