#!/usr/bin/env python3
"""Delete the forward declarations nothing needs.

Usage:
    python3 tools/dropprotos.py <file> [--delete]

A forward declaration earns its place only when something uses the function
before it is defined -- a caller higher up the file, a static table of handlers,
or mutual recursion.  This file carries 2,578 of them and about half are for
functions nothing mentions until after their own definition.  Those say nothing
the compiler does not already know by the time it matters.

**But a `static` declaration is not only a declaration.** A function definition
that follows one inherits internal linkage from it, which is why 1,817 of the
3,289 definitions here do not say `static` themselves and are static anyway.
Delete such a prototype and the function silently becomes external -- `nm` grows
a symbol, and this tree's whole claim is that `main` is the only one.

So a prototype is dropped only together with the repair: if its definition does
not carry `static`, the definition gets it.  Linkage is preserved by
construction rather than by hoping, and the caller's `nm` check is what proves
it afterwards.

Kept, necessarily:

  * anything used before it is defined, including from a file-scope table --
    `cmdnames[]` names six hundred handlers and sits above most of them;
  * one of every mutually recursive pair, which is the same rule seen from the
    other side;
  * anything with no definition in this file at all -- `osdef.h` declares libc
    functions the platform may not have, and those are not ours to remove.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil
import funcreach

IDENT = re.compile(r'\b[A-Za-z_]\w*\b')
PROTO = re.compile(r'^[A-Za-z_][A-Za-z0-9_ \t*]*?\b(\w+)\([^;\n]*\)[ \t]*;[ \t]*$', re.M)
# The two-line form: the attribute sits on a continuation and carries the `;`.
PROTO2 = re.compile(r'^[A-Za-z_][A-Za-z0-9_ \t*]*?\b(\w+)\([^;\n]*\)[ \t]*\n'
                    r'[ \t]+__attribute__[^;\n]*;[ \t]*$', re.M)


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
        sys.exit('dropprotos: only %d definitions found; the shape has moved '
                 'and acting on that would be reckless' % len(defs))

    # Where every identifier occurs, once.
    where = {}
    for m in IDENT.finditer(blanked):
        where.setdefault(m.group(0), []).append(m.start())

    protos = []
    for pat in (PROTO2, PROTO):
        for m in pat.finditer(blanked):
            protos.append((m.start(), m.end(), m.group(1)))
    protos.sort()

    droppable, kept_used, kept_nodef = [], 0, 0
    for start, end, name in protos:
        if name not in defs:
            kept_nodef += 1
            continue
        dstart, dend = defs[name]
        # Any mention that is neither this declaration nor inside the
        # definition itself, occurring before the definition begins.
        early = [p for p in where.get(name, ())
                 if p < dstart and not (start <= p < end)]
        if early:
            kept_used += 1
            continue
        droppable.append((start, end, name, dstart))

    needs_static = [n for _, _, n, d in droppable
                    if not re.match(r'[ \t]*static\b', text[d:text.index('\n', d)])]

    print('  dropprotos   %d declarations: %d droppable, %d used before their '
          'definition, %d with no definition here'
          % (len(protos), len(droppable), kept_used, kept_nodef))
    print('  dropprotos   %d of those definitions must gain `static`, or they '
          'become external' % len(needs_static))

    if not (droppable and delete):
        return

    # Apply from the end, so earlier offsets stay valid.
    edits = []
    for start, end, name, dstart in droppable:
        edits.append(('proto', start, end))
        line_end = text.index('\n', dstart)
        if not re.match(r'[ \t]*static\b', text[dstart:line_end]):
            indent = len(text[dstart:line_end]) - len(text[dstart:line_end].lstrip())
            edits.append(('static', dstart + indent, dstart + indent))
    for kind, a, b in sorted(edits, key=lambda e: -e[1]):
        if kind == 'proto':
            end = b
            while end < len(text) and text[end] == '\n':
                end += 1
            text = text[:a] + text[end:]
        else:
            text = text[:a] + 'static ' + text[a:]

    path.write_text(text, errors='surrogateescape')
    print('  dropprotos   %d removed, %d definitions made static explicitly'
          % (len(droppable), len(needs_static)))


if __name__ == '__main__':
    main()
