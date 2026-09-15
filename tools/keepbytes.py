#!/usr/bin/env python3
"""A byte that is not valid UTF-8 is kept as it is: read, shown, and written back unchanged.

Usage:
    python3 tools/keepbytes.py <file>

Phase 12 made UTF-8 the only encoding by cutting the conversion layer at its
entry points.  One consequence it did not declare: slim-vim reads a file that is
not valid UTF-8 by falling back to latin1, and writes its bytes back unchanged;
after Phase 12 there is no fallback, readfile() replaces every invalid byte with
'?' (bad_char_behavior's default, BAD_REPLACE), marks the buffer read-only, and
a forced :w writes the '?'s.  Measured: "ok\\n\\xff bad\\n" comes back as
"ok\\n? bad\\n" from every whim binary since Phase 12, and unchanged from
slim-vim and whim Phases 0 to 11.

The user chose what `++bad=keep` already did: the byte stays in the buffer as a
byte, displays as <ff>, is written back as it was, and the buffer is not made
read-only.  "[ILLEGAL BYTE in line N]" is still reported -- it describes the
file.  So keeping is the only behaviour, bad_char_behavior is always -1, and
every test of it folds:

  readfile() stops choosing a behaviour from ++bad, stops replacing or dropping
  the byte in the UTF-8 check and in the conversion loops, and stops making the
  buffer read-only for an illegal byte.

  ++bad goes from getargopt(), and get_bad_opt() and the buffer's b_bad_char go
  with it.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def literal(seg, old, new, what, count=1):
    n = seg.count(old)
    if n != count:
        sys.exit('keepbytes: %s -- occurs %d times, expected %d' % (what, n, count))
    print('  keepbytes    %s' % what)
    return seg.replace(old, new)


def subn(seg, pattern, new, what, count=1):
    seg, n = re.subn(pattern, new, seg, flags=re.M)
    if n != count:
        sys.exit('keepbytes: %s -- matched %d times, expected %d' % (what, n, count))
    print('  keepbytes    %s' % what)
    return seg


def fold_all(seg, pattern, what):
    """fold_never every occurrence, however many -- but at least one."""
    n = len(re.findall(pattern, seg, re.M))
    if n == 0:
        sys.exit('keepbytes: %s -- no occurrence' % what)
    try:
        seg = cutil.fold_never(seg, pattern, n, re.M)
    except ValueError as e:
        sys.exit('keepbytes: %s -- %s' % (what, e))
    print('  keepbytes    %s (%d)' % (what, n))
    return seg


def keep_then_chain(seg, pattern, what):
    """`if (T) { A } else if ... else { ... }` with T always true: keep A, lose the rest of the chain."""
    ms = list(re.finditer(pattern, seg, re.M))
    if len(ms) != 1:
        sys.exit('keepbytes: %s -- the condition occurs %d times, expected 1' % (what, len(ms)))
    b = cutil.blank(seg)
    k, o, c, head = cutil._guarded(seg, ms[0], b)
    if head != 'if':
        sys.exit('keepbytes: %s -- not a plain if' % what)
    body = cutil._dedent4(seg[seg.index('\n', o) + 1:seg.rfind('\n', 0, c) + 1])
    end = seg.index('\n', c) + 1
    while True:
        nxt = re.match(r'[ \t]*else\b', seg[end:])
        if not nxt:
            break
        o2 = b.index('{', end + nxt.end())
        c2 = cutil.match(seg, o2, b)
        end = seg.index('\n', c2) + 1
    print('  keepbytes    %s' % what)
    return seg[:k] + body + seg[end:]


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        sys.exit('keepbytes: %s is not defined at file scope' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    t = path.read_text(errors='surrogateescape')

    def read(s):
        s = subn(s, r'^[ \t]*if \(eap != NULL && eap->bad_char != 0\)\n[ \t]*\{\n[ \t]*bad_char_behavior = eap->bad_char;\n'
                    r'[ \t]*if \(set_options\)\n[ \t]*\{\n[ \t]*curbuf->b_bad_char = eap->bad_char;\n[ \t]*\}\n[ \t]*\}\n'
                    r'[ \t]*else\n[ \t]*\{\n[ \t]*curbuf->b_bad_char = 0;\n[ \t]*\}\n\n', '',
                 'readfile taking the behaviour from ++bad')
        # -1 means keep.  Drop (-2) never happens and neither does a replacement.
        s = fold_all(s, r'^[ \t]*if \(bad_char_behavior ==  \(-2\) \)$', 'an invalid byte dropped')
        # The spacing is the expander's: `(-1) )` alone, `(-1)  && (...)` with two.
        s = fold_all(s, r'^[ \t]*if \(bad_char_behavior !=  \(-1\)(?: \)|  && \(fio_flags != 0 \|\| iconv_fd != \(iconv_t\)-1\)\))$',
                     'an invalid byte replaced')
        # After the drop test folds, the conversion loop's chain starts with the keep test.
        s = keep_then_chain(s, r'^[ \t]*if \(bad_char_behavior ==  \(-1\) \)$', 'a converted invalid byte kept as it is')
        s = literal(s, ' || (illegal_byte > 0 && bad_char_behavior !=  (-1) )', '',
                    'an illegal byte making the buffer read-only')
        s = subn(s, r'^[ \t]*int[ \t]+bad_char_behavior = BAD_REPLACE;\n', '', 'readfile declaring the behaviour')
        if re.search(r'\bbad_char_behavior\b', s):
            sys.exit('keepbytes: readfile still names bad_char_behavior')
        return s
    t = in_function(t, 'readfile', read)

    def argopt(s):
        s = fold_all(s, r'^[ \t]*else if \( strncmp\(\(char \*\)\(arg\), \(char \*\)\("bad"\), \(3\)\)  == 0\)$', '++bad')
        s = keep_then_chain(s, r'^[ \t]*if \(pp == &eap->force_enc\)$', "++enc's value, the only one left to check")
        s = subn(s, r'^[ \t]*int[ \t]+bad_char_idx;\n', '', "getargopt's ++bad index")
        return s
    t = in_function(t, 'getargopt', argopt)

    if re.search(r'\bbad_char\b(?!_)', t.replace('int         bad_char;', '')):
        rest = [m.group(0).strip() for m in re.finditer(r'^[^\n]*\bbad_char\b[^\n]*$', t, re.M)
                if 'int         bad_char;' not in m.group(0) and 'get_bad_opt' not in m.group(0)]
        live = [r for r in rest if not r.startswith('eap->bad_char =')]
        if live:
            sys.exit('keepbytes: eap->bad_char still read: %s' % live)

    path.write_text(t, errors='surrogateescape')
    print('  keepbytes    an invalid byte is kept, and nothing can ask otherwise')


if __name__ == '__main__':
    main()
