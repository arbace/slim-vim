#!/usr/bin/env python3
"""The last two encoding options, and the default that outlived Phase 16.

Usage:
    python3 tools/nofencs.py <file>

Phase 16 emptied `'fileencodings'` and said so.  It was true at startup and not
afterwards: `set_option_default()` special-cases the option, so `:set fencs&`
restored `ucs-bom,utf-8,default,latin1` from `fencs_utf8_default` -- a third
reference that phase did not find, because it names the string rather than the
function the other two called.  Measured on the shipped binary before this was
written: `fileencodings=` at startup, `fileencodings=ucs-bom,utf-8,default,latin1`
after a reset.

Three readers, and with them the two options can finally go:

  * `set_option_default()` stops special-casing `'fileencodings'`, which is what
    makes Phase 16's claim true at every moment rather than one.
  * `readfile()` stops choosing between an empty `'fileencodings'` and a list to
    walk.  There is no list, so it takes the buffer's own `'fileencoding'`, which
    is the branch the empty case already took.
  * `did_set_encoding()` stops setting up a conversion between `'termencoding'`
    and `'encoding'`.  `convert_setup()` has answered CONV_NONE since Phase 16,
    so the block could only ever succeed at doing nothing.

`'encoding'` still cannot go, and this is where that stops being a temporary
state of affairs: `p_enc` is the NAME of the one encoding, compared against in
twenty-nine places.  Removing the option would mean removing the name, and the
name is doing work.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

EDITS = [
    ("the reset that restored a unicode 'fileencodings'",
     r'[ \t]*else if \(\(char_u \*\*\)varp == &p_fencs && enc_utf8\)\n'
     r'[ \t]*\{\n[ \t]*newval = fencs_utf8_default;\n[ \t]*\}\n', ''),
    ("readfile choosing between an empty list and a list",
     r'[ \t]*else if \(\*p_fencs == NUL\)\n[ \t]*\{\n'
     r'([ \t]*fenc = curbuf->b_p_fenc;\n[ \t]*fenc_alloced = FALSE;\n)'
     r'[ \t]*\}\n[ \t]*else\n[ \t]*\{\n'
     r'[ \t]*fenc_next = p_fencs;\n'
     r'[ \t]*fenc = next_fenc\(&fenc_next, &fenc_alloced\);\n[ \t]*\}\n',
     '    else\n    {\n\\1    }\n'),
]

# The third edit needs BRACE MATCHING and not a regex, for the reason this tree
# has now recorded three times: a lazy `(?:[^\n]*\n)*?\}` stops at the first
# line that is only a brace, which here is the inner `if (convert_setup(...))`'s
# -- leaving the outer `}` and the function's own `}` with nothing to close, and
# gcc reporting it as "expected identifier or '(' before 'return'".
TENC = r'^[ \t]*if \(\(\(varp == &p_enc && \*p_tenc != NUL\) \|\| varp == &p_tenc\)\)$'


def drop_tenc_block(text):
    blanked = cutil.blank(text)
    m = re.search(TENC, text, re.M)
    if not m:
        sys.exit("nofencs: did_set_encoding no longer converts between "
                 "'termencoding' and 'encoding'")
    lp = text.index('(', m.start())
    rp = cutil.match(text, lp, blanked)
    i = rp + 1
    while text[i] in ' \t\n':
        i += 1
    if text[i] != '{':
        sys.exit('nofencs: that condition does not open a block')
    close = cutil.match(text, i, blanked)
    end = close + 1
    while end < len(text) and text[end] in ' \t':
        end += 1
    if end < len(text) and text[end] == '\n':
        end += 1
    if text[end:end + 1] == '\n':
        end += 1
    return text[:m.start()] + text[end:]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    for what, pat, repl in EDITS:
        text, n = re.subn(pat, repl, text, flags=re.M)
        if n != 1:
            sys.exit('nofencs: %s -- expected 1, matched %d' % (what, n))
        print('  nofencs      %s' % what)

    text = drop_tenc_block(text)
    print("  nofencs      converting between 'termencoding' and 'encoding'")

    for var in ('p_fencs', 'p_tenc'):
        left = [m.start() for m in re.finditer(r'\b%s\b' % var, text)]
        # The declaration and the options[] row are not reads.
        if len(left) > 2:
            sys.exit('nofencs: %s still has %d mentions; the row cannot go '
                     'while anything reads it' % (var, len(left)))

    path.write_text(text, errors='surrogateescape')
    print('  nofencs      p_fencs and p_tenc are now declaration and row only')


if __name__ == '__main__':
    main()
