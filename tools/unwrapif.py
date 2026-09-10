#!/usr/bin/env python3
"""Unwrap a conditional group, keeping its body and deleting its directives.

Usage:
    python3 tools/unwrapif.py <file> <MACRO>

Removing a directive is a MATCHING problem, not a text substitution, and this
tool exists because getting that wrong is expensive in a way that does not look
like the mistake it was.  `#ifdef HAVE_CONFIG_H` spans fifty lines of vim.h.
Delete only its opening line and the orphaned `#endif` closes `#ifndef VIM__H`
instead -- three thousand lines early.  vim.h then stops guarding itself, and
because xdiff.h includes vim.h back, half of vim.h is processed twice per
translation unit.  What gcc reports is a redeclared enumerator in termdefs.h,
a file with no include guard of its own and no connection to any of it.

So: find the opening directive for MACRO, count directive depth forward to its
own `#endif`, and delete exactly those two lines.

It refuses when the group has an `#else` or `#elif` branch.  Unwrapping then
would mean choosing a branch, which is a different operation with a different
right answer -- that is what plant.py and resolve.py are for, and they decide
it by preprocessing rather than by reading the condition.
"""

import re
import sys

OPEN = re.compile(r'^\s*#\s*(if|ifdef|ifndef)\b')
MID = re.compile(r'^\s*#\s*(elif|elifdef|elifndef|else)\b')
CLOSE = re.compile(r'^\s*#\s*endif\b')


def unwrap(lines, macro):
    """Return (lines, opened_at, closed_at) with the two directives gone."""
    want = re.compile(r'^\s*#\s*if(def)?\s+' + re.escape(macro) + r'\b')
    start = None
    for i, line in enumerate(lines):
        if want.match(line):
            start = i
            break
    if start is None:
        raise SystemExit('unwrapif: no #ifdef %s here' % macro)

    depth = 0
    end = None
    for i in range(start, len(lines)):
        if OPEN.match(lines[i]):
            depth += 1
        elif CLOSE.match(lines[i]):
            depth -= 1
            if depth == 0:
                end = i
                break
        elif MID.match(lines[i]) and depth == 1:
            raise SystemExit(
                'unwrapif: #%s at line %d is a branch of the %s group -- '
                'unwrapping would mean choosing one, which is resolve.py\'s job'
                % (MID.match(lines[i]).group(1), i + 1, macro))
    if end is None:
        raise SystemExit('unwrapif: #ifdef %s at line %d is never closed'
                         % (macro, start + 1))

    return lines[:start] + lines[start + 1:end] + lines[end + 1:], start, end


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    path, macro = sys.argv[1], sys.argv[2]
    with open(path) as f:
        lines = f.readlines()
    new, start, end = unwrap(lines, macro)
    with open(path, 'w') as f:
        f.writelines(new)
    print('  unwrap       %s: %s spanned lines %d-%d, %d lines kept'
          % (path, macro, start + 1, end + 1, end - start - 1))


if __name__ == '__main__':
    main()
