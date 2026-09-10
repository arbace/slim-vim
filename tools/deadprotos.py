#!/usr/bin/env python3
"""Delete prototypes for functions that no longer exist.

Usage:
    python3 tools/deadprotos.py <vim.c>

The dead-code sweep keys on `-Wall`, and gcc says nothing at all about a
declaration of a function that is never defined and never called: it is a
promise about some other translation unit, and in a file that IS the whole
program that promise is simply false.

They matter because of what they keep alive.  `proftime_T` and `getoption_T`
survived a whole type sweep -- correctly, by that sweep's own rule -- because
each was still mentioned by one prototype, and a prototype is a root.  Delete
the prototype and the type becomes unreachable, which is why this runs inside
the same fixpoint loop rather than once.

The test is exact and needs no C parsing: a declaration at file scope whose
name appears NOWHERE else in the file.  A defined function's name appears at
least twice (its prototype and its definition), a called one more, so one
occurrence means nothing refers to it.

**Everywhere except osdef.h and xdiff.h.**  A prototype in this program's own
headers naming a function that does not exist is simply wrong.  Those two
blocks are not: osdef.h declares libc functions the platform may not have
declared, and xdiff.h declares the xdiff library's interface -- both describe
code that lives somewhere else by design, and deleting them because nothing
here calls them would be deleting a true statement.  Measured: the reference
vim.c keeps _Xmblen and all five xdl_* declarations, and keeps mmfile_t and
xpparam_t alive through them, while dropping alloc_id, proftime_time_left and
get_option_value from vim's own headers.
"""

import re
import sys
from collections import Counter
from pathlib import Path

# A prototype at file scope: type, name, parameter list, semicolon, all on one
# line -- which Phase 7 guarantees, having joined every parenthesised group.
PROTO = re.compile(r'^[A-Za-z_][A-Za-z0-9_ \t*]*?\b(\w+)\s*\([^;]*\)\s*;\s*$')
WORD = re.compile(r'[A-Za-z_]\w*')
DEFINE = re.compile(r'^[ \t]*#[ \t]*define[ \t]+(\w+)')


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    lines = path.read_text(errors='surrogateescape').split('\n')

    # A mention inside a #define body counts only if the MACRO is used.  An
    # unused macro's body is not a reference to anything -- alloc_id's only
    # other mention is inside ALLOC_ONE_ID, which nothing calls, and Phase 9
    # deletes 910 macros for exactly that reason.
    #
    # But ignoring every macro body is wrong in the other direction, and gcc
    # says so immediately: exestack and au_new_curbuf are named only from macro
    # bodies, and those macros are called all over the file.  So: live macros
    # contribute their bodies, dead ones do not, and liveness is itself a
    # fixpoint because a live macro can be what makes another one live.
    outside = Counter()
    defines = []
    for line in lines:
        m = DEFINE.match(line)
        if m:
            defines.append((m.group(1), line))
            continue
        outside.update(WORD.findall(line))

    seen = Counter(outside)
    live = set()
    while True:
        grew = False
        for name, line in defines:
            if name not in live and seen[name] > 0:
                live.add(name)
                seen.update(WORD.findall(line))
                grew = True
        if not grew:
            break

    KEEP = ('osdef.h', 'xdiff.h')
    protected = set()
    inside = None
    for i, line in enumerate(lines):
        if line.startswith('// ') and 'begin ' in line:
            inside = next((k for k in KEEP if 'begin ' + k in line), None)
        elif line.startswith('// ') and 'end ' in line and inside:
            if 'end ' + inside in line:
                inside = None
        if inside:
            protected.add(i)

    out = []
    dropped = []
    for i, line in enumerate(lines):
        m = PROTO.match(line) if i not in protected else None
        if m and seen[m.group(1)] == 1:
            dropped.append(m.group(1))
            continue
        out.append(line)

    if dropped:
        path.write_text('\n'.join(out), errors='surrogateescape')
    print('  deadprotos   %d declared, never defined, never called%s'
          % (len(dropped),
             ': ' + ', '.join(dropped[:4]) + ('...' if len(dropped) > 4 else '')
             if dropped else ''))


if __name__ == '__main__':
    main()
