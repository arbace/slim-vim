#!/usr/bin/env python3
"""Extract a phase heredoc's multi-line string literals as Go constants.

Usage:
    python3 tools/gocmp/genlits.py <phase-program> <prefix> > out.go
    e.g.  python3 tools/gocmp/genlits.py pipes/whim69-edit.sh w69 \\
              > tools/go/internal/edit/whim69lit.go

GENERATE, DO NOT TRANSCRIBE.  A phase that matches on a block of C carries it as
a triple-quoted string, and those blocks contain BLANK LINES.  whim65 is the
measurement: an OP_FUNCTION block retyped by hand had lost the blank lines
between its statements, the literal matched nothing, and the refusal was
`occurs 0 times, expected 1` -- which is the right refusal, arriving one port
late.  A filtered read of a phase program does not show blank lines at all, so
the error is invisible at the moment it is made.

It is the same call tools/gocmp/genmuslctype.py makes for muslctype's 230-line
C driver: retyping is where a changed byte becomes invisible to BOTH the compile
and the comparison.

The names are the Python's own where the literal is a module-level assignment
(OLD_ARG becomes w69OldArg) and <prefix>litN in source order otherwise, so a
port reads against names that mean something where the phase gave them one.

Run it against the phase program AS IT WAS when it still had the heredoc:

    git show <rev>:pipes/whim70-edit.sh > /tmp/p.sh
    python3 tools/gocmp/genlits.py /tmp/p.sh w70

This tool is named by no phase program, so it enters no implementation key.
"""
import ast
import re
import sys


def heredoc(path):
    """The Python inside `python3 - "$f" <<'TAG' ... TAG`, all of them joined."""
    src = open(path, errors='surrogateescape').read().split('\n')
    out, i = [], 0
    while i < len(src):
        m = re.match(r"\s*python3 -.*<<'?(\w+)'?\s*$", src[i])
        if m:
            tag, j = m.group(1), i + 1
            while j < len(src) and src[j].strip() != tag:
                out.append(src[j])
                j += 1
            i = j
        i += 1
    return '\n'.join(out)


def goquote(v):
    return '"' + (v.replace('\\', '\\\\').replace('"', '\\"')
                   .replace('\n', '\\n').replace('\t', '\\t')) + '"'


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    path, prefix = sys.argv[1], sys.argv[2]
    tree = ast.parse(heredoc(path))

    seen, lits, n = set(), [], 0
    for node in tree.body:
        if (isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant)
                and isinstance(node.value.value, str) and '\n' in node.value.value):
            name = prefix + node.targets[0].id.title().replace('_', '')
            lits.append((name, node.value.value))
            seen.add(node.value.value)
    for node in ast.walk(tree):
        if (isinstance(node, ast.Constant) and isinstance(node.value, str)
                and '\n' in node.value and node.value not in seen):
            n += 1
            seen.add(node.value)
            lits.append(('%slit%d' % (prefix, n), node.value))

    if not lits:
        sys.exit('genlits: %s has no multi-line literals' % path)

    print('package edit\n')
    print("// The multi-line literals %s matches on, EXTRACTED from the phase's" % path)
    print('// heredoc by tools/gocmp/genlits.py rather than retyped.  They carry BLANK')
    print('// LINES, which a filtered read of a phase program does not show, and a')
    print('// literal that is 90%% right matches nothing.  See that tool for the')
    print('// measurement.')
    print('const (')
    for name, v in lits:
        print('\t%s = %s' % (name, goquote(v)))
    print(')')


if __name__ == '__main__':
    main()
