#!/usr/bin/env python3
r"""Give internal linkage to every named symbol, in one pass over the file.

Usage:
    python3 tools/makestatic.py <file> <symbol> ...
    python3 tools/makestatic.py <file> --from <file-of-symbols>

Phase 8 used to do this one symbol at a time: `nm` the object, then for each
external name spawn a python process that read the whole translation unit,
rewrote it, and wrote it back.  With 2,045 externals and a seven-megabyte file
that is 2,045 reads and 2,045 writes -- **148 seconds, forty per cent of the
phase**, to make a set of edits that touch one line each.

The work does not need a process per symbol, and it does not need a regex per
symbol either.  A file-scope declaration names exactly one thing, so one pass
that asks "what does this line declare, and is that name in the set?" is
O(lines), where the old shape was O(lines x symbols).

Everything else is phase 8's rule, unchanged, and each part of it was learned
the hard way:

  * **Every file-scope occurrence, not the first.**  Objects do not inherit
    internal linkage -- a definition with no storage class is external whatever
    a prior static declaration said, and gcc rejects the pair outright with
    "non-static declaration follows static declaration".
  * **`extern` is replaced, not prefixed.**  Two storage classes in one
    declaration is an error, and the globals block is written with `extern`.
  * **The keyword goes at the START of the declaration**, which for a function
    definition is the line above: the return type is indented on its own line
    with the name at column 0.  Prefixing the name's line gives
    `static empty_curbuf(...)` under a line that already says `static int`.
  * **A line only counts as a return type if it looks like one** -- an
    identifier and qualifiers, nothing else.  Testing "does not end in a
    semicolon" instead walks back onto whatever precedes, and a `#define`
    acquires a `static` in front of its `#`.
  * **A name that is a function-like macro is left alone.**  A prototype whose
    name is a macro declares the expansion, not itself; making `mch_rename`
    static declares libc's `rename` static.
"""

import re
import sys
from pathlib import Path

# What a file-scope declaration looks like: column 0, a type or storage class,
# then the name, then whatever a declaration or definition may open with.  The
# terminator is deliberately loose -- two prototypes carry their attribute on a
# continuation line, so their own line ends in `)`.
DECL = re.compile(r'^(?!static\b)([A-Za-z_][A-Za-z0-9_ \t*()\[\]]*?)\b(\w+)\s*[(\[;=,)]')
TYPELINE = re.compile(r'^[ \t]*[A-Za-z_][A-Za-z0-9_ \t*]*$')


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    if sys.argv[2] == '--from':
        want = set(Path(sys.argv[3]).read_text().split())
    else:
        want = set(sys.argv[2:])
    if not want:
        print('  makestatic   nothing to do')
        return

    text = path.read_text(errors='surrogateescape')
    lines = text.split('\n')

    # A name that is a function-like macro declares its expansion, not itself.
    macros = set(re.findall(r'^# *define  *(\w+)\(', text, re.M))
    skipped = sorted(want & macros)
    want -= macros

    def start_of(i):
        j = i - 1
        while j >= 0 and lines[j].strip() == '':
            j -= 1
        if j >= 0 and TYPELINE.match(lines[j]):
            return j
        return i

    hit = {}
    for i, l in enumerate(lines):
        m = DECL.match(l)
        if not m or m.group(2) not in want:
            continue
        k = start_of(i)
        if lines[k].lstrip().startswith('static'):
            continue
        if lines[k].startswith('extern '):
            lines[k] = 'static ' + lines[k][len('extern '):]
        else:
            indent = len(lines[k]) - len(lines[k].lstrip())
            lines[k] = lines[k][:indent] + 'static ' + lines[k][indent:]
        hit[m.group(2)] = hit.get(m.group(2), 0) + 1

    missed = sorted(want - set(hit))
    if missed:
        sys.exit('makestatic: no file-scope declaration of %s%s'
                 % (', '.join(missed[:6]), '...' if len(missed) > 6 else ''))

    path.write_text('\n'.join(lines), errors='surrogateescape')
    print('  makestatic   %d names, %d declarations, in one pass%s'
          % (len(hit), sum(hit.values()),
             '; %d macro names left alone' % len(skipped) if skipped else ''))


if __name__ == '__main__':
    main()
