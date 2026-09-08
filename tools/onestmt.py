"""One statement per line.

Split on top-level semicolons only.  A `for (a; b; c)` header keeps its
semicolons because they are inside parens, and an initialiser table keeps its
rows because the split is on `;`, not `,`.

A label (`case X:`, `default:`) stays with nothing after it, on its own line.

Usage: onestmt.py <file>
"""
import re
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

LABEL_HEAD = re.compile(r'^\s*(case\b|default\b|[A-Za-z_]\w*\s*:)')


def split_line(line):
    s = line.rstrip()
    if not s.strip() or s.lstrip().startswith('#') or s.lstrip().startswith('//'):
        return [line]
    indent = s[:len(s) - len(s.lstrip())]
    b = cutil.blank(s)
    d = cutil.depths(b)
    out = []

    # A label, if any, goes on its own line.  Find its colon in the *blanked*
    # text: `case ':':` has two colons inside a character constant and
    # splitting on the first of those produces `case ':` and a syntax error.
    if LABEL_HEAD.match(s):
        colon = -1
        for j in range(len(b)):
            if b[j] == ':' and d[j] == 0:
                if b[j:j + 2] == '::' or (j and b[j - 1] == ':'):
                    continue
                if b[j + 1:j + 2] == ':':
                    continue
                colon = j
                break
        if colon >= 0 and s[colon + 1:].strip():
            out.append(indent + s[:colon + 1].strip())
            indent = indent + '    '
            s = indent + s[colon + 1:].strip()
            b = cutil.blank(s)
            d = cutil.depths(b)

    pieces, start = [], 0
    for j in range(len(b)):
        if b[j] == ';' and d[j] == 0:
            pieces.append(s[start:j + 1])
            start = j + 1
    tail = s[start:]
    if tail.strip():
        pieces.append(tail)
    if len(pieces) <= 1 and not out:
        return [line]
    for piece in pieces:
        t = piece.strip()
        if t:
            out.append(indent + t)
    return out or [line]


def main():
    path = sys.argv[1]
    lines = open(path, encoding='utf-8', errors='surrogateescape').read().split('\n')
    out, changed = [], 0
    for line in lines:
        got = split_line(line)
        if len(got) > 1:
            changed += 1
        out.extend(got)
    text = '\n'.join(out)
    if not text.endswith('\n'):
        text += '\n'
    open(path, 'w', encoding='utf-8', errors='surrogateescape').write(text)
    print('%d lines split; %d lines -> %d' % (changed, len(lines), len(out)))


if __name__ == '__main__':
    main()
