#!/usr/bin/env python3
"""UTF-8, and no other encoding, ever.

Usage:
    python3 tools/noenc.py <file>

Phase 13 made `'encoding'` a property of the build rather than of the machine.
This makes it not a setting at all: `mb_init()` accepts utf-8 and returns
"invalid argument" for anything else, so `:set enc=latin1` fails the way a
misspelt value fails, and the latin1 and DBCS character paths become
unreachable and are swept.

**The conversion layer is cut at its entry points, not unpicked from its
callers**, and that is the whole shape of this phase.  `readfile()` is 1,758
lines with conversion woven through a retry loop, partial-character carry-over
and a `goto retry`; `buf_write()` is much the same.  Excising that by hand is
the kind of surgery that compiles, passes a symbol check and corrupts a file on
some path nobody tested.  Instead:

  * `my_iconv_open()` returns failure, which is a value both readfile() and
    buf_write() already handle -- it is what happens on a system without iconv,
    which is a case upstream supports and tests.  Every iconv path in them is
    then the path not taken.
  * `convert_setup()` produces CONV_NONE, and `string_convert()` returns NULL.
    Both are the "nothing to do" answers their callers already branch on.
  * `check_for_bom()` finds none and `make_bom()` writes none.  A byte-order
    mark becomes three ordinary bytes at the top of the buffer, which is what
    ignoring it means.

Nothing is restructured; six functions answer differently, and the sweep takes
`convert_setup_ext`, `string_convert_ext`, `iconv_string` and the rest because
nothing reaches them any more.

`'encoding'` itself CANNOT be dropped even though it is PV_NONE: its row is
what initialises `p_enc`, which is read in twenty-nine places, so removing it
would leave a NULL global -- the trap Phase 14 recorded, in its other form.  It
stays, reports utf-8, and refuses anything else.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

# The dispatch in mb_init(): everything from the first `else if` that sniffs a
# prefix down to the enc_latin1like line, replaced by the one case left.
OLD_DISPATCH_START = '    else if ( strncmp((char *)(p_enc), (char *)("8bit-"), (5))  == 0'
NEW_DISPATCH = '''    if ( strcmp((char *)(p_enc), (char *)("utf-8"))  != 0)
    {
        return e_invalid_argument;
    }

    enc_unicode = 0;
    enc_utf8 = TRUE;
    enc_dbcs = 0;
    has_mbyte = TRUE;
    enc_latin1like = TRUE;
'''

# mb_init() installs a default 'fileencodings' whenever the encoding is unicode
# and the user has not set one.  With enc_utf8 now always true that fires at
# every startup, and it reaches the option BY NAME -- set_string_option_direct
# ("fencs", ...) -- so dropping the row turns it into E685 and then a segfault
# before the first keystroke.  There is nothing left to put in the list.
DROP_FENCS = (
    '    if (enc_utf8 && !option_was_set((char_u *)"fencs"))\n'
    '    {\n        set_fencs_unicode();\n    }\n\n')

# And a second caller, which the first sweep does not remove because it is not
# dead: set_option_default() special-cases 'fileencodings' so that RESETTING it
# picks the unicode list rather than the compiled default.  With no conversion
# there is no list to pick.
DROP_FENCS_DEFAULT = (
    '            if (options[opt_idx].var == (char_u *)&p_fencs && enc_utf8)\n'
    '            {\n                set_fencs_unicode();\n            }\n'
    '            else if (options[opt_idx].indir != PV_NONE)\n',
    '            if (options[opt_idx].indir != PV_NONE)\n')

STUBS = [
    ('my_iconv_open',  '    return (void *)(iconv_t)-1;'),
    ('convert_setup',  '    vcp->vc_type = CONV_NONE;\n'
                       '    vcp->vc_factor = 1;\n'
                       '    vcp->vc_fail = FALSE;\n'
                       '    return OK;'),
    ('string_convert', '    return NULL;'),
    ('check_for_bom',  '    *lenp = 0;\n    return NULL;'),
    ('make_bom',       '    return 0;'),
    ('convert_input_safe', '    if (restp != NULL)\n    {\n        *restp = NULL;\n'
                           '    }\n    return len;'),
]


# The last two symbols, and the only place this phase touches readfile() or
# buf_write().  my_iconv_open() now always fails, so every one of these blocks
# is a branch that can no longer be taken -- but the calls inside them are what
# keep `iconv` and `iconv_close` in the symbol table, and a dependency that is
# linked in and never reached is exactly what this pipeline exists to remove.
#
# Each is a brace-matched `if` with no `else`, deleted whole.  They are the
# open, the use and the close, twice over.
# EVERY ANCHOR NAMES A LINE OF THE BODY, not just the condition.  `if
# (fio_flags == 0)` occurs twice in readfile() and the first one has an `else`
# after it; deleting that block left an orphaned `else`, which gcc reported as
# "expected '}' before 'else'" and then as two undefined labels six hundred
# lines away.  The same shape as funcreach.py's two regex bugs: a span that
# ended in the wrong place.
ICONV_BLOCKS = [
    (r'^[ \t]*if \(ip->bw_iconv_fd != \(iconv_t\)-1\)\n[ \t]*\{\n[ \t]*const char',
     "buf_write's conversion"),
    (r'^[ \t]*if \(converted && wb_flags == 0\)\n[ \t]*\{\n'
     r'[ \t]*write_info\.bw_iconv_fd = \(iconv_t\)my_iconv_open',
     "buf_write's iconv open"),
    (r'^[ \t]*if \(write_info\.bw_iconv_fd != \(iconv_t\)-1\)\n[ \t]*\{\n'
     r'[ \t]*iconv_close', "buf_write's iconv close"),
    (r'^[ \t]*if \(fio_flags == 0\)\n[ \t]*\{\n'
     r'[ \t]*iconv_fd = \(iconv_t\)my_iconv_open', "readfile's iconv open"),
    (r'^[ \t]*if \(iconv_fd != \(iconv_t\)-1\)\n[ \t]*\{\n[ \t]*iconv_close',
     "readfile's iconv close"),
    (r'^[ \t]*if \(iconv_fd != \(iconv_t\)-1\)\n[ \t]*\{\n[ \t]*const char',
     "readfile's conversion loop"),
    # Two more closes, nested deeper: one where the read loop gives up on a
    # conversion, one in readfile's exit path.  Indentation differs, the body
    # does not.
    (r'^[ \t]*if \(iconv_fd != \(iconv_t\)-1\)\n[ \t]*\{\n'
     r'[ \t]*iconv_close\(iconv_fd\);\n[ \t]*iconv_fd = \(iconv_t\)-1;\n[ \t]*\}',
     "the read loop giving up on a conversion"),
    (r'^[ \t]*if \(iconv_fd != \(iconv_t\)-1\)\n[ \t]*\{\n'
     r'[ \t]*iconv_close\(iconv_fd\);\n[ \t]*\}', "readfile's exit path"),
]


def drop_if_block(text, pat, what):
    """Delete an `if (...)` and the block it guards, by matching braces."""
    blanked = cutil.blank(text)
    import re as _re
    m = _re.search(pat, text, _re.M)
    if not m:
        sys.exit('noenc: %s is not where this expects' % what)
    lp = text.index('(', m.start())
    rp = cutil.match(text, lp, blanked)
    i = rp + 1
    while text[i] in ' \t\n':
        i += 1
    if text[i] != '{':
        sys.exit('noenc: %s does not open a block' % what)
    close = cutil.match(text, i, blanked)
    # An `else` after the block means deleting the block alone changes which
    # branch runs, and leaves the `else` with no `if`.
    tail = text[close + 1:close + 40]
    if _re.match(r'[ \t]*\n[ \t]*else\b', tail):
        sys.exit('noenc: %s has an else branch; deleting the if alone would '
                 'orphan it' % what)
    end = close + 1
    while end < len(text) and text[end] in ' \t':
        end += 1
    if end < len(text) and text[end] == '\n':
        end += 1
    if text[end:end + 1] == '\n':
        end += 1
    return text[:m.start()] + text[end:]


def replace_body(text, name, body):
    blanked = cutil.blank(text)
    m = re.search(r'^%s\([^\n]*\n' % re.escape(name), text, re.M)
    if not m:
        sys.exit('noenc: %s is not defined at file scope any more' % name)
    opening = blanked.index('{', m.end())
    close = cutil.match(text, opening, blanked)
    if close < 0:
        sys.exit('noenc: %s is unbalanced' % name)
    was = text.count('\n', opening, close)
    return text[:opening] + '{\n' + body + '\n}' + text[close + 1:], was


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    # --- mb_init: one encoding ------------------------------------------
    i = text.find(OLD_DISPATCH_START)
    if i < 0:
        sys.exit("noenc: mb_init's encoding dispatch is not where this expects")
    end_marker = '\n    enc_latin1like = '
    j = text.index(end_marker, i)
    j = text.index('\n', j + len(end_marker)) + 1
    text = text[:i] + NEW_DISPATCH + text[j:]
    print('  noenc        mb_init accepts utf-8 and rejects every other value')

    # The function-pointer table: keep the utf-8 arm, drop the other two.
    blanked = cutil.blank(text)
    k = text.index('    if (enc_utf8)\n    {\n        mb_ptr2len = utfc_ptr2len;')
    o1 = blanked.index('{', k)
    c1 = cutil.match(text, o1, blanked)
    rest = text[c1 + 1:]
    m = re.match(r'\n    else if \(enc_dbcs != 0\)\n', rest)
    if not m:
        sys.exit('noenc: the dbcs arm does not follow the utf-8 arm')
    o2 = blanked.index('{', c1 + 1 + m.end())
    c2 = cutil.match(text, o2, blanked)
    m2 = re.match(r'\n    else\n', text[c2 + 1:])
    if not m2:
        sys.exit('noenc: the latin1 arm does not follow the dbcs arm')
    o3 = blanked.index('{', c2 + 1 + m2.end())
    c3 = cutil.match(text, o3, blanked)
    body = text[text.index('\n', o1) + 1:text.rfind('\n', 0, c1) + 1]
    body = ''.join(l[4:] if l.startswith('    ') else l
                   for l in body.splitlines(keepends=True))
    text = text[:k] + body + text[c3 + 1:].lstrip('\n')
    print('  noenc        the latin1 and DBCS character paths lose their only caller')

    if DROP_FENCS not in text:
        sys.exit("noenc: mb_init no longer installs a default 'fileencodings', "
                 "so either this has run already or that code has moved")
    text = text.replace(DROP_FENCS, '', 1)
    print("  noenc        mb_init stops installing a default 'fileencodings'")

    # The row stays -- readfile() dereferences p_fencs, so removing the row
    # would leave a NULL global -- and its content goes instead.  An empty
    # 'fileencodings' is the branch readfile already takes when the user has
    # emptied it, which is the behaviour wanted here.
    before = text
    # The compiled default is "ucs-bom"; the longer unicode list was the one
    # mb_init() installed at run time, and that has just gone.
    text = re.sub(r'(\{"fileencodings","fencs",[^\n]*\n[^\n]*\n[ \t]*\{\(char_u \*\))'
                  r'"[^"]*"', r'\1""', text)
    if text == before:
        sys.exit("noenc: 'fileencodings' does not default to the unicode list, "
                 "so this has run already or the row has moved")
    print("  noenc        'fileencodings' defaults to empty; nothing to try")

    if DROP_FENCS_DEFAULT[0] not in text:
        sys.exit("noenc: set_option_default no longer special-cases "
                 "'fileencodings', so this has run already or that code moved")
    text = text.replace(*DROP_FENCS_DEFAULT, 1)
    print("  noenc        resetting 'fileencodings' stops picking a unicode list")

    # --- the conversion layer answers "nothing to do" -------------------
    total = 0
    for name, stub in STUBS:
        text, was = replace_body(text, name, stub)
        total += was
        print('  noenc        %-20s was %3d lines, is now a constant answer'
              % (name, was))

    for pat, what in ICONV_BLOCKS:
        text = drop_if_block(text, pat, what)
        print('  noenc        %s, a branch that can no longer be taken' % what)

    path.write_text(text, errors='surrogateescape')
    print('  noenc        %d lines stubbed; nothing calls iconv any more' % total)


if __name__ == '__main__':
    main()
