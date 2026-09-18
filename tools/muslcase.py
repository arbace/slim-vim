"""musl's Unicode case mapping, as a table `zero-vim.c` can carry itself.

Usage: python3 tools/muslcase.py --generate            write the table text
       python3 tools/muslcase.py --verify <file.c>     check a source's tables

`zero-vim.c` called `towupper()` and `towlower()` from `utf_toupper()` and
`utf_tolower()`, and zero phase 15 vendors them.  musl implements both with a
two-level base-6 packed table (`src/ctype/casemap.h`, 297 lines, 16,998 bytes)
and forty lines of bit arithmetic, which is exactly what this repository's
"obvious, simple, idiomatic C" rule is not.  But the SAME MAPPING fits the shape
`zero-vim.c` already has: `convertStruct` rows of {rangeStart, rangeEnd, step,
offset}, searched by `utf_convert()`, which is how vim carries its own case
tables.  Range-compressed, musl's mapping is 187 + 171 rows -- the same size as
vim's own 198 + 183 -- and it is read by a function that is already there.

THE TABLE IS DATA THE TREE CANNOT DERIVE, and this is what keeps it from being
a remembered constant: `--verify` compares it against THE LIBC THIS MACHINE
LINKS, through ctypes, over every one of the 1,114,112 codepoints.  So the
phase's check does not trust the bytes it shipped; it re-derives the answer from
the only authority there is and requires exact agreement.  A musl upgrade that
moved one codepoint would fail the phase rather than pass it quietly.

MEASURED when this was written: 2,742 codepoints have a mapping, 187 upper
ranges, 171 lower; the whole sweep costs 2.4 seconds in Python.
"""
import ctypes
import re
import sys

PLANES = 0x110000


def libc():
    c = ctypes.CDLL(None)
    for name in ('towupper', 'towlower'):
        f = getattr(c, name)
        f.restype = ctypes.c_int
        f.argtypes = [ctypes.c_int]
    return c.towupper, c.towlower


def compress(delta):
    """{codepoint: offset} -> convertStruct rows, greedily.

    A row is {start, end, step, offset}: the same offset applied to every
    `step`-th codepoint in [start, end].  `utf_convert()` binary-searches on
    rangeEnd, so the rows must come out ascending and non-overlapping, which a
    single forward pass over sorted codepoints gives for free.
    """
    out = []
    for c in sorted(delta):
        d = delta[c]
        if out:
            s, e, st, off = out[-1]
            if off == d:
                if st == 1 and c == e + 1:
                    out[-1] = (s, c, 1, off)
                    continue
                if s == e and c - e >= 2:
                    out[-1] = (s, c, c - e, off)
                    continue
                if st > 1 and c - e == st:
                    out[-1] = (s, c, st, off)
                    continue
        out.append((c, c, 1, d))
    return out


def expand(rows):
    m = {}
    for s, e, st, off in rows:
        for c in range(s, e + 1, st):
            m[c] = off
    return m


def mapping():
    up, low = libc()
    u, l = {}, {}
    for c in range(PLANES):
        d = up(c) - c
        if d:
            u[c] = d
        d = low(c) - c
        if d:
            l[c] = d
    return u, l


def emit(name, rows):
    body = ',\n'.join('        {0x%x,0x%x,%d,%d}' % r for r in rows)
    return 'static convertStruct %s[] =\n{\n%s\n};\n' % (name, body)


WRAPPERS = '''
    static int
musl_towupper(int a)
{
    return utf_convert(a, musl_toUpper, (int)sizeof(musl_toUpper));
}

    static int
musl_towlower(int a)
{
    return utf_convert(a, musl_toLower, (int)sizeof(musl_toLower));
}
'''


def generate():
    u, l = mapping()
    up, low = compress(u), compress(l)
    for rows, want in ((up, u), (low, l)):
        if expand(rows) != want:
            sys.exit('muslcase: the compression is not exact')
    return '\n' + emit('musl_toUpper', up) + '\n' + emit('musl_toLower', low) + WRAPPERS


def rows_of(text, name):
    m = re.search(r'^static convertStruct %s\[\] =\n\{\n(.*?)\n\};$' % name,
                  text, re.M | re.S)
    if not m:
        return None
    return [tuple(int(x, 0) for x in r)
            for r in re.findall(r'\{(0x[0-9a-f]+),(0x[0-9a-f]+),(-?\d+),(-?\d+)\}', m.group(1))]


def verify(path):
    text = open(path, errors='surrogateescape').read()
    up = rows_of(text, 'musl_toUpper')
    low = rows_of(text, 'musl_toLower')
    if up is None or low is None:
        sys.exit('muslcase: %s has no musl_toUpper[]/musl_toLower[]' % path)
    fu, fl = expand(up), expand(low)
    cu, cl = libc()
    bad = []
    for c in range(PLANES):
        if c + fu.get(c, 0) != cu(c):
            bad.append(('upper', c, c + fu.get(c, 0), cu(c)))
        if c + fl.get(c, 0) != cl(c):
            bad.append(('lower', c, c + fl.get(c, 0), cl(c)))
        if len(bad) > 8:
            break
    if bad:
        for kind, c, got, want in bad:
            print('  muslcase     %s U+%04X: the table says %04X, this libc says %04X'
                  % (kind, c, got, want))
        sys.exit(1)
    print('  muslcase     %d + %d convertStruct rows, and every one of the %d codepoints '
          'maps as THIS MACHINE\'S libc maps it -- the table is re-derived from the only '
          'authority there is, not trusted' % (len(up), len(low), PLANES))


if __name__ == '__main__':
    if len(sys.argv) == 2 and sys.argv[1] == '--generate':
        sys.stdout.write(generate())
    elif len(sys.argv) == 3 and sys.argv[1] == '--verify':
        verify(sys.argv[2])
    else:
        sys.exit(__doc__.splitlines()[2].strip())
