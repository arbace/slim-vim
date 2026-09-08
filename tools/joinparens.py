"""Join every parenthesised group onto one line.

Conditions of if/while/for/switch, and the argument lists of calls,
declarations and definitions.  After this a condition's extent is one line and
a line-oriented tool never has to parse C to find it.

One linear scan.  "Find one, fix it, rescan from the top" is O(n^2) and does
not finish on a file this size: carry the current line, pull in following lines
while its parens are unbalanced, and re-examine the joined line.

Braces are not counted.  A line ending in `,` inside braces is a table row, not
a wrapped argument list, and joining those would put a 600-entry table on one
line.

Usage: joinparens.py <file>
"""
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def paren_balance(line):
    b = cutil.blank(line)
    return b.count('(') - b.count(')') + b.count('[') - b.count(']')


def main():
    path = sys.argv[1]
    lines = open(path, encoding='utf-8', errors='surrogateescape').read().split('\n')
    out = []
    i = 0
    joined = 0
    n = len(lines)
    while i < n:
        cur = lines[i]
        i += 1
        if cur.lstrip().startswith('#') or cur.lstrip().startswith('//'):
            out.append(cur)
            continue
        depth = paren_balance(cur)
        while depth > 0 and i < n:
            nxt = lines[i]
            if nxt.lstrip().startswith('#'):
                break
            i += 1
            joined += 1
            sep = '' if cur.endswith('(') or cur.endswith('[') or not cur.strip() else ' '
            if nxt.lstrip().startswith(')') or nxt.lstrip().startswith(','):
                sep = ''
            cur = cur.rstrip() + sep + nxt.strip()
            depth = paren_balance(cur)
        out.append(cur)
    text = '\n'.join(out)
    if not text.endswith('\n'):
        text += '\n'
    open(path, 'w', encoding='utf-8', errors='surrogateescape').write(text)
    print('%d lines joined; %d lines -> %d' % (joined, n, len(out)))


if __name__ == '__main__':
    main()
