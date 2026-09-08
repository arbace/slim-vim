"""Give every if/else/for/while/do body a brace block.

The point is not style.  Everything after this needs to know where a body
begins and ends; make it syntactic and the tools stop parsing C, leave it
implicit and every later pass is a fresh chance to get an extent wrong.

Runs after joinparens.py and splitheads.py, so a head is a whole line ending in
`)` (or the word `else` or `do`) and a body starts on the next line.

Traps this handles:
  * `} while (cond);` is the tail of a do-while, not a head -- a head line never
    ends in `;`.
  * `else if (...)` is one statement: the `if` is the head, not the body.
  * a `do` body's terminating `while (...)` stays outside the braces.
  * a statement can span lines when it contains an initialiser list, so the end
    is "brace depth back to zero and the line ends in `;`", not "the next `;`".

Usage: brace.py <file>
"""
import re
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

HEAD = re.compile(r'^(\s*)(?:\}\s*)?(if|for|while|switch)\s*\(')
ELSE_IF = re.compile(r'^(\s*)else\s+if\s*\(')
ELSE = re.compile(r'^(\s*)else\s*$')
DO = re.compile(r'^(\s*)do\s*$')


def is_skippable(line):
    s = line.strip()
    return not s or s.startswith('#') or s.startswith('//')


def next_code(lines, i):
    while i < len(lines) and is_skippable(lines[i]):
        i += 1
    return i


def head_of(line, index=None, do_terms=()):
    """(indent, kind) if this line is a control head with a body, else None.

    A `while` that terminates a do-while is not a head.  Usually it says so by
    ending in `;`, but it can also be written

        }
        while (cond)
            ;

    with the semicolon on its own line, and then it is indistinguishable from a
    real while-head by looking at the line alone.  Those are found in a first
    pass and passed in as do_terms.
    """
    s = line.rstrip()
    if is_skippable(s):
        return None
    if index is not None and index in do_terms:
        return None
    body = s.strip()
    if body.endswith(';'):
        return None                      # `while (cond);` closing a do
    m = DO.match(s)
    if m:
        return (m.group(1), 'do')
    m = ELSE.match(s)
    if m:
        return (m.group(1), 'else')
    m = ELSE_IF.match(s)
    if m and s.endswith(')'):
        return (m.group(1), 'if')
    m = HEAD.match(s)
    if m and s.endswith(')'):
        # Only an `if` may swallow a following `else`.  A for/while/switch that
        # happens to be an if's body must not: doing so puts the closing brace
        # on the far side of the else and moves the else's body inside the loop.
        return (m.group(1), 'if' if m.group(2) == 'if' else 'loop')
    return None


def stmt_end(lines, i, do_terms=()):
    """Index of the last line of the statement starting at line i."""
    i = next_code(lines, i)
    if i >= len(lines):
        return i
    h = head_of(lines[i], i, do_terms)
    if h is not None:
        kind = h[1]
        j = next_code(lines, i + 1)
        e = stmt_end(lines, j, do_terms)
        if kind == 'do':
            k = next_code(lines, e + 1)
            if k < len(lines) and re.match(r'^\s*(\}\s*)?while\b', lines[k]):
                # The do-while ends at its semicolon, which is not always on
                # the same line as the `while`.
                while k < len(lines) and not lines[k].rstrip().endswith(';'):
                    k += 1
                return k
            return e
        if kind == 'if':
            k = next_code(lines, e + 1)
            if k < len(lines) and re.match(r'^\s*(\}\s*)?else\b', lines[k]):
                return stmt_end(lines, k, do_terms)
        return e
    # a plain statement, or a brace block
    depth = 0
    started = False
    j = i
    while j < len(lines):
        if is_skippable(lines[j]):
            j += 1
            continue
        b = cutil.blank(lines[j])
        depth += b.count('{') - b.count('}')
        if '{' in b:
            started = True
        s = lines[j].rstrip()
        if depth <= 0 and (s.endswith(';') or (started and s.endswith('}'))):
            return j
        if depth <= 0 and s.endswith(':'):
            return j
        j += 1
    return len(lines) - 1


def main():
    path = sys.argv[1]
    lines = open(path, encoding='utf-8', errors='surrogateescape').read().split('\n')
    # Find the do-terminating `while` lines first, to a fixpoint: identifying
    # one can change the extent of an enclosing statement, which can reveal
    # another.
    do_terms = set()
    for _ in range(5):
        found = set()
        for i, line in enumerate(lines):
            h = head_of(line, i, do_terms)
            if h is None or h[1] != 'do':
                continue
            j = next_code(lines, i + 1)
            e = stmt_end(lines, j, do_terms)
            k = next_code(lines, e + 1)
            if k < len(lines) and re.match(r'^\s*(\}\s*)?while\b', lines[k]):
                found.add(k)
        if found == do_terms:
            break
        do_terms |= found
    print('%d do-terminating while lines identified' % len(do_terms))

    opens, closes = {}, {}
    braced = 0
    for i, line in enumerate(lines):
        h = head_of(line, i, do_terms)
        if h is None:
            continue
        indent = h[0]
        j = next_code(lines, i + 1)
        if j >= len(lines):
            continue
        if lines[j].strip().startswith('{'):
            continue
        e = stmt_end(lines, j, do_terms)
        opens.setdefault(i, []).append(indent)
        closes.setdefault(e, []).append(indent)
        braced += 1
    out = []
    for i, line in enumerate(lines):
        out.append(line)
        for indent in opens.get(i, []):
            out.append(indent + '{')
        for indent in reversed(closes.get(i, [])):
            out.append(indent + '}')
    # a close for line e and an open for line e cannot both be right; the loop
    # above emits opens first, which is the order they nest in.
    text = '\n'.join(out)
    if not text.endswith('\n'):
        text += '\n'
    open(path, 'w', encoding='utf-8', errors='surrogateescape').write(text)
    print('%d bodies braced; %d lines -> %d' % (braced, len(lines), len(out)))


if __name__ == '__main__':
    main()
