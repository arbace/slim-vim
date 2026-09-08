"""Parse and rewrite conditional-directive groups.

The rule this exists to enforce: do not evaluate the conditions.  Plant a
unique token in every branch of every group, preprocess once, and keep the
branches whose token comes out.  The preprocessor is the only thing that knows
-- definedness is position-dependent (an include guard is defined at the *end*
of preprocessing) and a macro can reach one translation unit and not another.

Importing does nothing.
"""
import os
import re

OPEN = re.compile(r'^\s*#\s*(if|ifdef|ifndef)\b')
MID = re.compile(r'^\s*#\s*(elif|elifdef|elifndef|else)\b')
CLOSE = re.compile(r'^\s*#\s*endif\b')
DEFINE = re.compile(r'^\s*#\s*define\s+(\w+)')


class Group:
    """A #if ... #elif ... #else ... #endif chain."""
    __slots__ = ('branches', 'open_line', 'end_line')

    def __init__(self):
        self.branches = []      # list of (directive_line_index, [children])
        self.open_line = None
        self.end_line = None


def parse(lines, start=0, depth=0):
    """Return (nodes, index_after).  A node is an int (a plain line) or Group."""
    nodes = []
    i = start
    while i < len(lines):
        ln = lines[i]
        if OPEN.match(ln):
            g = Group()
            g.open_line = i
            body, i = parse(lines, i + 1, depth + 1)
            g.branches.append((g.open_line, body))
            while i < len(lines) and MID.match(lines[i]):
                mid = i
                body, i = parse(lines, i + 1, depth + 1)
                g.branches.append((mid, body))
            if i < len(lines) and CLOSE.match(lines[i]):
                g.end_line = i
                i += 1
            else:
                raise SyntaxError('unterminated group opened at line %d' % (g.open_line + 1))
            nodes.append(g)
            continue
        if MID.match(ln) or CLOSE.match(ln):
            if depth == 0:
                raise SyntaxError('stray %r at line %d' % (ln.strip(), i + 1))
            return nodes, i
        nodes.append(i)
        i += 1
    if depth:
        raise SyntaxError('unterminated group')
    return nodes, i


def walk(nodes):
    """Yield every Group, outermost first."""
    for n in nodes:
        if isinstance(n, Group):
            yield n
            for _, body in n.branches:
                yield from walk(body)


def is_include_guard(g, lines):
    """A whole-file include guard: the group wraps the file and its first body
    line defines the macro its condition names.

    These must not be resolved.  Within one translation unit the true branch is
    taken exactly once, so the markers say "always live" -- and removing the
    guard is precisely what makes a header able to be read twice.  vim.h
    includes xdiff.h, which includes vim.h back; only the guard stops that.
    They go in the merge, when nothing can be included twice.
    """
    body = g.branches[0][1]
    first = next((n for n in body if isinstance(n, int) and lines[n].strip()), None)
    if first is None:
        return False
    m = DEFINE.match(lines[first])
    if not m:
        return False
    if m.group(1) not in lines[g.open_line]:
        return False
    after = [n for n in range(g.end_line + 1, len(lines)) if lines[n].strip()]
    return not after
