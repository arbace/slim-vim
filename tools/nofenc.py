#!/usr/bin/env python3
r"""The last two per-buffer encoding options.

Usage:
    python3 tools/nofenc.py <file>

`'fileencoding'` names the encoding a buffer was read in and will be written
back in, and `'bomb'` whether it had a byte-order mark.  With one encoding and
no BOM, both have had one possible value since Phase 16 -- but unlike the six
options Phase 20 took, these are not plumbing: eight functions read them, and
each has to be looked at.

  * `buf_write()` takes the buffer's `'fileencoding'` as the target and asks
    `need_conversion()`.  The answer for an empty string is "no", which is the
    honest one now, so it passes the empty string.
  * `buf_write()` writes a BOM when `'bomb'` is set.  `make_bom()` has written
    nothing since Phase 16, so the block was already a call that returned 0.
  * `readfile()` takes the buffer's `'fileencoding'` when there is no list to
    walk, and sets `'bomb'` when it strips one.  `check_for_bom()` has found
    none since Phase 16, so the only assignment that could fire is the one
    clearing it.
  * `bomb_size()` answers how many bytes of the file are a BOM, for the
    `g CTRL-G` byte count.  None of them are.
  * `save_file_ff()` and `file_ff_differs()` remember the encoding and the BOM a
    file was read with, so `:w` can warn that they changed.  Neither can change.
    `'fileformat'`, `'endofline'` and `'endoffile'` still can, and those parts
    stay.
  * `utf_find_illegal()` -- `g8` -- sets up a conversion from `'encoding'` to
    the buffer's `'fileencoding'` to find a byte that is illegal in it.  With
    one encoding there is nothing to convert between.
  * `add_b0_fenc()` writes the encoding name into a swap file's block zero.
    There have been no swap files since Phase 15.

What is left after this is `'encoding'`, alone, reporting utf-8.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

STUBS = [('bomb_size', '    return 0;'), ('add_b0_fenc', '')]

EDITS = [
    ("buf_write taking the buffer's 'fileencoding' as its target",
     r'([ \t]*else\n[ \t]*\{\n)[ \t]*fenc = buf->b_p_fenc;\n',
     r'\1        fenc = (char_u *)"";\n'),
    ("readfile taking the buffer's 'fileencoding' when there is no list",
     r'[ \t]*fenc = curbuf->b_p_fenc;\n', '        fenc = (char_u *)"";\n'),
    ("readfile setting 'bomb' after stripping one",
     r'[ \t]*if \(set_options\)\n[ \t]*\{\n'
     r'[ \t]*curbuf->b_p_bomb = TRUE;\n'
     r'[ \t]*curbuf->b_start_bomb = TRUE;\n[ \t]*\}\n', ''),
    ("readfile clearing it, twice",
     r'[ \t]*curbuf->b_p_bomb = FALSE;\n', '', 2),
    # The test is longer than it looks: the 'bomb' term is one of four in a
    # nested disjunction, and only that term goes.
    ("the BOM this build never has, in readfile's first-block test",
     r'!curbuf->b_p_bomb && tmpname == NULL', 'tmpname == NULL'),
    ("save_file_ff remembering the BOM and the encoding",
     r'[ \t]*buf->b_start_bomb = buf->b_p_bomb;\n\n'
     r'[ \t]*if \(buf->b_start_fenc == NULL \|\|  strcmp[^\n]*\n[ \t]*\{\n'
     r'[ \t]*vim_free\(buf->b_start_fenc\);\n'
     r'[ \t]*buf->b_start_fenc = vim_strsave\(buf->b_p_fenc\);\n[ \t]*\}\n', ''),
    ("file_ff_differs comparing them",
     r'[ \t]*if \(!buf->b_p_bin && buf->b_start_bomb != buf->b_p_bomb\)\n'
     r'[ \t]*\{\n[ \t]*return TRUE;\n[ \t]*\}\n'
     r'[ \t]*if \(buf->b_start_fenc == NULL\)\n[ \t]*\{\n'
     r'[ \t]*return \(\*buf->b_p_fenc != NUL\);\n[ \t]*\}\n'
     r'[ \t]*return \( strcmp[^\n]*\n', '    return FALSE;\n'),
    ("g8 converting to the buffer's 'fileencoding' to find an illegal byte",
     r'[ \t]*if \(enc_utf8 && \(enc_canon_props\(curbuf->b_p_fenc\) & ENC_8BIT\)\)\n'
     r'[ \t]*\{\n[ \t]*convert_setup\(&vimconv, p_enc, curbuf->b_p_fenc\);\n[ \t]*\}\n', ''),
    ("buf_write writing a BOM it no longer makes",
     None, None),   # brace-matched below
    # What the two options leave behind once nothing compares them: the
    # remembered copies, written on every read and looked at by nobody.  A
    # struct field is not a variable, so no warning reports it and the sweep
    # cannot see it -- which is why these are listed rather than swept.
    ("the remembered BOM and encoding a file was read with",
     r'^[ \t]*char_u[ \t]*\*b_start_fenc;\n', ''),
    ("them, in buf_T",
     r'^[ \t]*int[ \t]*b_start_bomb;\n', ''),
    ("freeing the remembered encoding",
     r'^[ \t]* vim_free\(buf->b_start_fenc\);\n[ \t]* \(buf->b_start_fenc\) = NULL;\n', ''),
    ("clearing the remembered BOM",
     r'^[ \t]*(?:cur)?buf->b_start_bomb = FALSE;\n', '', 3),
    ("did_set_encoding's arm for 'fileencoding'",
     None, None),   # brace-matched below
    ("the empty test Phase 19 left in did_set_encoding",
     r'\n[ \t]*if \(errmsg == NULL\)\n[ \t]*\{\n[ \t]*\}\n', ''),
    # gvarp existed to ask which of the three encoding options was being set.
    # There is one.  -Wunused-but-set-variable is not a shape deadsweep.py
    # deletes, so it goes here.
    # THREE LOOKUPS BY NAME, and the reason this phase needed two attempts.
    # set_string_option_direct((char_u *)"fenc", ...) resolves the option
    # through findoption(), which answers -1 for a row that is not there; the
    # caller does not check, so silent Ex mode exits 1 without printing
    # anything, and every recorded exit status in the harness moves at once.
    # Phase 19 met the same thing as "fencs".  dropoptions.py's name guard
    # would have caught it, but that guard is --strict and --local skips it.
    ("readfile recording the encoding it read a file in",
     r'\n[ \t]*if \(set_options\)\n[ \t]*\{\n'
     r'[ \t]*set_string_option_direct\(\(char_u \*\)"fenc",[^\n]*\n[ \t]*\}\n', '\n'),
    ("`:e ++enc=` forcing one",
     r'[ \t]*char_u \*fenc = enc_canonize\(eap->cmd \+ eap->force_enc\);\n\n'
     r'[ \t]*if \(fenc != NULL\)\n[ \t]*\{\n'
     r'[ \t]*set_string_option_direct\(\(char_u \*\)"fenc",[^\n]*\n[ \t]*\}\n'
     r'[ \t]*vim_free\(fenc\);\n', ''),
    ("reading one out of a recovered swap file's block zero",
     r'[ \t]*if \(b0p-> b0_fname\[B0_FNAME_SIZE_ORG - 2\]  & B0_HAS_FENC\)\n'
     r'[ \t]*\{\n[ \t]*int fnsize = B0_FNAME_SIZE_NOCRYPT;\n\n'
     r'[ \t]*for \(p = b0p->b0_fname \+ fnsize; p > b0p->b0_fname && p\[-1\] != NUL; --p\)\n'
     r'[ \t]*\{\n[ \t]*;\n[ \t]*\}\n'
     r'[ \t]*b0_fenc = vim_strnsave\(p, b0p->b0_fname \+ fnsize - p\);\n[ \t]*\}\n\n?', ''),
    ("the local it was read into",
     r'^[ \t]*char_u[ \t]*\*b0_fenc = NULL;\n', ''),
    ("a recovered swap file restoring one",
     r'[ \t]*if \(b0_fenc != NULL\)\n[ \t]*\{\n'
     r'[ \t]*set_option_value_give_err\(\(char_u \*\)"fenc",[^\n]*\n'
     r'[ \t]*vim_free\(b0_fenc\);\n[ \t]*\}\n', ''),
    ("the local that asked which encoding option was being set",
     r'^[ \t]*char_u[ \t]*\*\*gvarp;\n', ''),
    ("its one assignment",
     r'^[ \t]*gvarp = \(char_u \*\*\)get_option_varp_scope\(args->os_idx, OPT_GLOBAL\);\n\n?', ''),
]


def drop_if_block(text, pat, what):
    blanked = cutil.blank(text)
    m = re.search(pat, text, re.M)
    if not m:
        sys.exit('nofenc: %s is not where this expects' % what)
    lp = text.index('(', m.start())
    rp = cutil.match(text, lp, blanked)
    i = rp + 1
    while text[i] in ' \t\n':
        i += 1
    close = cutil.match(text, i, blanked)
    end = close + 1
    while end < len(text) and text[end] in ' \t':
        end += 1
    if end < len(text) and text[end] == '\n':
        end += 1
    return text[:m.start()] + text[end:]


def drop_bom_write(text):
    """The `if (buf->b_p_bomb && ...)` block, matched rather than scanned."""
    blanked = cutil.blank(text)
    m = re.search(r'^[ \t]*if \(buf->b_p_bomb && !write_bin', text, re.M)
    if not m:
        sys.exit('nofenc: buf_write no longer writes a BOM')
    lp = text.index('(', m.start())
    rp = cutil.match(text, lp, blanked)
    i = rp + 1
    while text[i] in ' \t\n':
        i += 1
    close = cutil.match(text, i, blanked)
    end = close + 1
    while end < len(text) and text[end] in ' \t':
        end += 1
    if end < len(text) and text[end] == '\n':
        end += 1
    return text[:m.start()] + text[end:]


def replace_body(text, name, body):
    blanked = cutil.blank(text)
    m = re.search(r'^%s\([^\n]*\n' % re.escape(name), text, re.M)
    if not m:
        sys.exit('nofenc: %s is not defined at file scope any more' % name)
    o = blanked.index('{', m.end())
    c = cutil.match(text, o, blanked)
    return text[:o] + '{\n' + (body + '\n' if body else '') + '}' + text[c + 1:]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    for edit in EDITS:
        what, pat, repl = edit[0], edit[1], edit[2]
        if pat is None:
            if 'BOM it no longer makes' in what:
                text = drop_bom_write(text)
            else:
                text = drop_if_block(text, r'^[ \t]*if \(gvarp == &p_fenc\)$', what)
        else:
            want = edit[3] if len(edit) > 3 else 1
            text, n = re.subn(pat, repl, text, flags=re.M)
            if n != want:
                sys.exit('nofenc: %s -- expected %d, matched %d' % (what, want, n))
        print('  nofenc       %s' % what)

    for name, body in STUBS:
        text = replace_body(text, name, body)
        print('  nofenc       %s answers for a file that has no BOM' % name)

    path.write_text(text, errors='surrogateescape')


if __name__ == '__main__':
    main()
