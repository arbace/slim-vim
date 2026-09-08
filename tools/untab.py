"""Expand tabs to spaces at the 8-column stops they were written for.

A tab inside a string or character literal is *data*, not layout: expanding it
would change the program.  Those become the escape \\t, which is the same
character to the compiler and no character to a text editor.

A tab inside a comment is layout and is expanded like any other; comments do
not survive the next pass anyway.

Usage: untab.py <file> ...
"""
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

TABSTOP = 8


def convert(s):
    b = cutil.blank(s)                 # literals and comments blanked
    c = cutil.strip_comments_only(s)   # only comments blanked
    out = []
    col = 0
    expanded = escaped = 0
    for i, ch in enumerate(s):
        if ch == '\n':
            out.append(ch)
            col = 0
            continue
        if ch == '\t':
            in_literal = b[i] != '\t' and c[i] == '\t'
            if in_literal:
                out.append('\\t')
                col += 2
                escaped += 1
            else:
                pad = TABSTOP - (col % TABSTOP)
                out.append(' ' * pad)
                col += pad
                expanded += 1
            continue
        out.append(ch)
        col += 1
    return ''.join(out), expanded, escaped


def main():
    files = exp = esc = 0
    for p in sys.argv[1:]:
        s = open(p, encoding='utf-8', errors='surrogateescape').read()
        if '\t' not in s:
            continue
        t, e, k = convert(s)
        open(p, 'w', encoding='utf-8', errors='surrogateescape').write(t)
        files += 1
        exp += e
        esc += k
    print('%d tabs expanded, %d turned into \\t, in %d files' % (exp, esc, files))


if __name__ == '__main__':
    main()
