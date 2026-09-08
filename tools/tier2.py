"""Compare two preprocessed files as C token streams.

`gcc -E -P` keeps horizontal whitespace and line structure, so a change that
only moves tokens around shows up as a textual difference and is not one.
Collapsing whitespace is not enough either -- `(int);` and `(int) ;` are the
same two tokens with different spacing.  Tokenise.

Usage: tier2.py <a.i> <b.i>
"""
import re
import sys

TOKEN = re.compile(r'''
      "(?:[^"\\\n]|\\.)*"          # string literal
    | '(?:[^'\\\n]|\\.)*'          # character constant
    | [A-Za-z_]\w*                 # identifier or keyword
    | \.?\d(?:[eEpP][+-]|[\w.])*   # pp-number
    | \S                           # any other single character
''', re.X)


def tokens(path):
    text = open(path, encoding='utf-8', errors='surrogateescape').read()
    return TOKEN.findall(text)


def main():
    a, b = tokens(sys.argv[1]), tokens(sys.argv[2])
    if a == b:
        print('TIER 2: token-identical (%d tokens)' % len(a))
        return 0
    print('token counts: %d vs %d' % (len(a), len(b)))
    for i in range(min(len(a), len(b))):
        if a[i] != b[i]:
            print('first difference at token %d' % i)
            print('  a: %s' % ' '.join(a[max(0, i - 12):i + 12]))
            print('  b: %s' % ' '.join(b[max(0, i - 12):i + 12]))
            break
    return 1


if __name__ == '__main__':
    sys.exit(main())
