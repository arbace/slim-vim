"""Splice out backslash line continuations.

This is exactly what translation phase 2 does, so it cannot change the token
stream -- including inside a #define body, a string literal or a // comment.
There is no line length limit to respect.

Usage: splice.py <file> ...
"""
import sys


def main():
    total_files = total_joins = 0
    for p in sys.argv[1:]:
        s = open(p, encoding='utf-8', errors='surrogateescape').read()
        n = s.count('\\\n')
        if not n:
            continue
        # A backslash before a newline splices, whatever precedes it.  Trailing
        # whitespace between the backslash and the newline is not a splice in
        # standard C, and gcc warns about it; there is none here (checked).
        out = s.replace('\\\n', '')
        open(p, 'w', encoding='utf-8', errors='surrogateescape').write(out)
        total_files += 1
        total_joins += n
    print('%d continuations spliced in %d files' % (total_joins, total_files))


if __name__ == '__main__':
    main()
