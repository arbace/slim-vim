"""Unwrap the `do { ... } while (0)` wrappers macro expansion leaves behind.

The construct exists so a macro body is one statement that swallows a
semicolon.  There are no macros.

**Brace matching, not a regex.**  An anchored pattern gets the common case and
fails on the rest: 18 lines here carry *two* wrappers, one of them nested, and
some are written `while (0);` and some `while (0) ;`.  Find `do {`, match the
brace, then require `while (0)` and a semicolon after it.  Repeat until the line
has none left, which handles nesting innermost-outward for free.

Phase 7 canonicalised before Phase 9 expanded, so every wrapper sits on one
line and its body has several statements on it.  Splitting the result on
top-level semicolons therefore restores the one-statement-per-line invariant as
a side effect.

A body holding `break` or `continue` would bind to a different loop once the
wrapper is gone; the tool refuses rather than guessing.

Unlike bracing, this **does** change code generation: at -O0 the never-taken
`while (0)` test is a real branch.  What must not change is data, so compare
.rodata and .data rather than the whole binary.

Usage: undowhile.py <file>
"""
import re
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

DO = re.compile(r'\bdo\s*\{')
TAIL = re.compile(r'^\s*while\s*\(\s*0\s*\)\s*;')


def unwrap_once(line, lineno):
    """Replace the first wrapper on the line with its body.  None if none."""
    b = cutil.blank(line)
    m = DO.search(b)
    if not m:
        return None
    open_i = b.index('{', m.start())
    close_i = cutil.match(line, open_i, b)
    if close_i < 0:
        raise SystemExit('line %d: unbalanced do-block' % lineno)
    t = TAIL.match(b[close_i + 1:])
    if not t:
        raise SystemExit('line %d: `do {` is not a do-while(0): %r'
                         % (lineno, line[m.start():close_i + 30]))
    body = line[open_i + 1:close_i]
    for kw in ('break', 'continue'):
        if re.search(r'\b%s\b' % kw, cutil.blank(body)):
            raise SystemExit('line %d: body holds %s, which would bind to a '
                             'different loop' % (lineno, kw))
    return line[:m.start()] + ' ' + body + ' ' + line[close_i + 1 + t.end():]


def statements(text):
    b = cutil.blank(text)
    d = cutil.depths(b)
    out, start = [], 0
    for i in range(len(b)):
        if b[i] == ';' and d[i] == 0:
            out.append(text[start:i + 1].strip())
            start = i + 1
    tail = text[start:].strip()
    if tail:
        out.append(tail)
    # a bare `;` here is what an empty wrapper collapsed to
    return [s for s in out if s and s != ';']


def main():
    path = sys.argv[1]
    lines = open(path, encoding='utf-8', errors='surrogateescape').read().split('\n')
    out = []
    wrappers = vanished = produced = touched = 0
    for n, line in enumerate(lines, 1):
        if not DO.search(cutil.blank(line)):
            out.append(line)
            continue
        touched += 1
        indent = line[:len(line) - len(line.lstrip())]
        cur = line
        while True:
            nxt = unwrap_once(cur, n)
            if nxt is None:
                break
            cur = nxt
            wrappers += 1
        stmts = statements(cur)
        if not stmts:
            vanished += 1
            continue
        for s in stmts:
            out.append(indent + s)
        produced += len(stmts)
    text = '\n'.join(out)
    if not text.endswith('\n'):
        text += '\n'
    open(path, 'w', encoding='utf-8', errors='surrogateescape').write(text)
    print('%d wrappers on %d lines unwrapped; %d lines vanished entirely, '
          '%d statements placed one per line' % (wrappers, touched, vanished, produced))


if __name__ == '__main__':
    main()
