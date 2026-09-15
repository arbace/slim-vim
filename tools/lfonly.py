#!/usr/bin/env python3
"""Only LF text files: no 'binary', no 'fileformat', no end-of-line bookkeeping.

Usage:
    python3 tools/lfonly.py <file>

A line ends with LF when it is read and gets LF when it is written, and a CR is a
character like any other.  So a file is never detected as DOS or Mac, never read
or written byte-exact, and always ends with LF when written.  whim50.sh drops -b
and the rows of 'binary', 'fileformat', 'fileformats', 'endofline',
'fixendofline', 'endoffile', 'textmode' and 'textauto'; this removes what a row
cannot:

  readfile() stops choosing a format -- from ++ff, 'binary' or 'fileformats' --
  and stops detecting one: the DOS/Mac detection, the Mac loop, CR stripping and
  its retry, the CTRL-Z tail and the "[CR missing]" message fold.  A file whose
  last line has no LF is still read, and still reported as "[noeol]"; that is
  the file, not an option.

  buf_write() writes LF after every line, the last included, and no CTRL-Z.

  ++bin, ++nobin, ++ff and ++fileformat go from getargopt(); ++enc and ++bad are
  the UTF-8 phase's.

  Everything that compared a buffer's format with the one it was read in --
  file_ff_differs(), save_file_ff(), set_file_options() -- has nothing left to
  compare, so its callers fold and the sweep takes it, with get_fileformat(),
  set_fileformat(), default_fileformat(), msg_add_fileformat() and
  set_options_bin().  -b reading stdin and fifos byte-exact goes with it.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def literal(seg, old, new, what, count=1):
    n = seg.count(old)
    if n != count:
        sys.exit('lfonly: %s -- occurs %d times, expected %d' % (what, n, count))
    print('  lfonly       %s' % what)
    return seg.replace(old, new)


def subn(seg, pattern, new, what, count=1):
    seg, n = re.subn(pattern, new, seg, flags=re.M)
    if n != count:
        sys.exit('lfonly: %s -- matched %d times, expected %d' % (what, n, count))
    print('  lfonly       %s' % what)
    return seg


def fold(seg, pattern, what, kind='never', count=1):
    try:
        seg = (cutil.fold_never if kind == 'never' else cutil.fold_always)(seg, pattern, count, re.M)
    except ValueError as e:
        sys.exit('lfonly: %s -- %s' % (what, e))
    print('  lfonly       %s' % what)
    return seg


def keep_then(seg, pattern, what):
    """An `if (T) { A } else { B }` whose condition is always true: keep A, lose B.

    cutil.fold_always refuses a block with an else, rightly -- it cannot tell
    whether the else is meant.  Here it is meant, so this does the one shape by
    the same brace matching fold_never uses.
    """
    ms = list(re.finditer(pattern, seg, re.M))
    if len(ms) != 1:
        sys.exit('lfonly: %s -- the condition occurs %d times, expected 1' % (what, len(ms)))
    b = cutil.blank(seg)
    k, o, c, head = cutil._guarded(seg, ms[0], b)
    if head != 'if':
        sys.exit('lfonly: %s -- not a plain if' % what)
    end = seg.index('\n', c) + 1
    rest = seg[end:]
    nxt = re.match(r'[ \t]*else\b', rest)
    if not nxt or re.match(r'[ \t]*else[ \t]+if\b', rest):
        sys.exit('lfonly: %s -- expected a plain else after the block' % what)
    o2 = b.index('{', end + nxt.end())
    c2 = cutil.match(seg, o2, b)
    body = cutil._dedent4(seg[seg.index('\n', o) + 1:seg.rfind('\n', 0, c) + 1])
    print('  lfonly       %s' % what)
    return seg[:k] + body + seg[seg.index('\n', c2) + 1:]


def drop_if(seg, pattern, what):
    n = len(re.findall(pattern, seg, re.M))
    if n != 1:
        sys.exit('lfonly: %s -- the condition occurs %d times, expected 1' % (what, n))
    try:
        seg = cutil.drop_if(seg, pattern, flags=re.M)
    except ValueError as e:
        sys.exit('lfonly: %s -- %s' % (what, e))
    print('  lfonly       %s' % what)
    return seg


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        sys.exit('lfonly: %s is not defined at file scope' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    t = path.read_text(errors='surrogateescape')

    # --- readfile ------------------------------------------------------------------
    def read(s):
        s = literal(s, '    set_file_options(set_options, eap);\n', '', 'readfile setting the format from ++ff and ++bin')
        # The two guarded calls first: the bare-call pattern matches their lines too.
        s = subn(s, r'^[ \t]*if \(set_options\)\n[ \t]*\{\n[ \t]*save_file_ff\(curbuf\);\n[ \t]*\}\n', '',
                 'readfile saving the format it read', 2)
        s = subn(s, r'^[ \t]*save_file_ff\(curbuf\);\n', '', 'readfile saving the format of a new file')
        s = subn(s, r'^[ \t]*if \(set_options\)\n[ \t]*\{\n[ \t]*if \(!read_buffer\)\n[ \t]*\{\n'
                    r'[ \t]*curbuf->b_p_eof = FALSE;\n[ \t]*curbuf->b_start_eof = FALSE;\n'
                    r'[ \t]*curbuf->b_p_eol = TRUE;\n[ \t]*curbuf->b_start_eol = TRUE;\n[ \t]*\}\n[ \t]*\}\n\n', '',
                 "readfile resetting 'endofline' and 'endoffile'")
        s = subn(s, r"^[ \t]*try_(?:mac|dos|unix) = \(vim_strchr\(p_ffs, '[mdx]'\) != NULL\);\n", '',
                 "readfile reading 'fileformats'", 6)
        # The format chain first: its 'binary' link is an `else if (curbuf->b_p_bin)`
        # too, until the ++ff link before it folds and makes it an `if`.
        s = fold(s, r'^[ \t]*if \(eap != NULL && eap->force_ff != 0\)$', 'readfile honouring ++ff')
        s = fold(s, r'^[ \t]*if \(curbuf->b_p_bin\)$', "readfile honouring 'binary'")
        s = fold(s, r'^[ \t]*else if \(curbuf->b_p_bin\)$', "readfile reading 'binary' as no encoding")
        s = subn(s, r'^[ \t]*if \(\*p_ffs == NUL\)\n[ \t]*\{\n[ \t]*fileformat = get_fileformat\(curbuf\);\n[ \t]*\}\n'
                    r'[ \t]*else\n[ \t]*\{\n[ \t]*fileformat =  \(-1\) ;\n[ \t]*\}\n', '',
                 "readfile choosing between 'fileformat' and detection")
        s = fold(s, r'^[ \t]*if \(!curbuf->b_p_eol\)$', "readfile dropping a filter's last LF")
        s = literal(s, 'if (size < 2 || curbuf->b_p_bin)', 'if (size < 2)', "readfile's BOM check under 'binary'")
        s = literal(s, 'else if (enc_utf8 && !curbuf->b_p_bin)', 'else if (enc_utf8)', "readfile's UTF-8 check under 'binary'")
        # The detection block tests fileformat == -1 again inside itself, so the
        # outer test is the one followed by the try_dos || try_unix test.
        s = fold(s, r'^[ \t]*if \(fileformat ==  \(-1\) \)(?=\n[ \t]*\{\n[ \t]*if \(try_dos \|\| try_unix\)$)',
                 'readfile detecting DOS and Mac line ends')
        s = fold(s, r'^[ \t]*if \(linerest != 0 && !curbuf->b_p_bin && fileformat == EOL_DOS && ptr\[-1\] == Ctrl_Z\)$',
                 "readfile's CTRL-Z at the end of a DOS file")
        s = fold(s, r'^[ \t]*if \(fileformat == EOL_MAC\)$', 'readfile splitting lines at CR')
        s = fold(s, r'^[ \t]*if \(fileformat == EOL_DOS\)$', 'readfile stripping CR, and retrying as Unix')
        s = subn(s, r'^[ \t]*if \(set_options\)\n[ \t]*\{\n[ \t]*curbuf->b_p_eol = FALSE;\n[ \t]*\}\n', '',
                 "readfile clearing 'endofline' for a missing last LF")
        s = fold(s, r'^[ \t]*if \(ff_error == EOL_DOS\)$', 'the "[CR missing]" message')
        s = drop_if(s, r'^[ \t]*if \(msg_add_fileformat\(fileformat\)\)$', 'the "[dos]" and "[mac]" read messages')
        s = literal(s, '    curbuf->b_no_eol_lnum = read_no_eol_lnum;\n', '', "readfile remembering the no-LF line for 'binary'")
        s = fold(s, r'^[ \t]*if \(keep_fileformat\)$', 'readfile keeping a format across a retry')
        return s
    t = in_function(t, 'readfile', read)

    # --- buf_write --------------------------------------------------------------------
    def write(s):
        s = subn(s, r'^[ \t]*if \(eap != NULL && eap->force_bin != 0\)\n[ \t]*\{\n[ \t]*write_bin = \(eap->force_bin == FORCE_BIN\);\n'
                    r'[ \t]*\}\n[ \t]*else\n[ \t]*\{\n[ \t]*write_bin = buf->b_p_bin;\n[ \t]*\}\n\n', '',
                 "buf_write choosing 'binary' or ++bin")
        s = subn(s, r'^[ \t]*int[ \t]+write_bin;\n', '', 'buf_write declaring write_bin')
        s = literal(s, '        fileformat = get_fileformat_force(buf, eap);\n', '', 'buf_write choosing a format')
        s = subn(s, r'^[ \t]*int[ \t]+fileformat;\n', '', 'buf_write declaring the format')
        s = fold(s, r'^[ \t]*else if \(c == CAR && fileformat == EOL_MAC\)$', 'buf_write writing CR as a line end')
        s = literal(s, 'if (end == 0 || (lnum == end && (write_bin || !buf->b_p_fixeol) && ((write_bin && lnum == buf->b_no_eol_lnum) || (lnum == buf->b_ml.ml_line_count && !buf->b_p_eol))))',
                    'if (end == 0)', 'buf_write leaving the last LF off')
        s = keep_then(s, r'^[ \t]*if \(fileformat == EOL_UNIX\)$', 'buf_write writing CR LF or CR')
        s = fold(s, r'^[ \t]*if \(!buf->b_p_fixeol && buf->b_p_eof\)$', 'buf_write appending CTRL-Z')
        s = drop_if(s, r'^[ \t]*if \(msg_add_fileformat\(fileformat\)\)$', 'the "[dos]" and "[mac]" write messages')
        return s
    t = in_function(t, 'buf_write', write)

    # --- open_buffer: stdin and fifos were read as 'binary' -------------------------------
    def openbuf(s):
        s = subn(s, r'^[ \t]*int[ \t]+save_bin = curbuf->b_p_bin;\n\n?', '', "open_buffer saving 'binary'", 2)
        s = subn(s, r'^[ \t]*if \(read_fifo\)\n[ \t]*\{\n[ \t]*curbuf->b_p_bin = TRUE;\n[ \t]*\}\n', '', 'a fifo read as binary')
        s = subn(s, r'^[ \t]*curbuf->b_p_bin = save_bin;\n', '', "open_buffer restoring 'binary'", 2)
        s = subn(s, r'^[ \t]*curbuf->b_p_bin = TRUE;\n', '', 'stdin read as binary')
        s = literal(s, '    save_file_ff(curbuf);\n', '', 'open_buffer saving the format')
        return s
    t = in_function(t, 'open_buffer', openbuf)

    # --- the rest ----------------------------------------------------------------------------
    t = in_function(t, 'do_ecmd', lambda s: subn(s, r'^[ \t]*set_file_options\(TRUE, eap\);\n', '', 'do_ecmd setting ++ff and ++bin'))
    # 'endofline' and 'endoffile' had no initialiser in buf_copy_options(): their
    # only resets were the ones removed above, in readfile() and buf_clear_file().
    # tools/droplocal.py wants an initialiser to recognise the shape, so their
    # field and get_varp() case go here.
    t = subn(t, r'^[ \t]*int[ \t]+b_p_eo[lf];\n', '', "the 'endofline' and 'endoffile' fields", 2)
    t = in_function(t, 'get_varp', lambda s: subn(
        s, r'^[ \t]*case   \(idopt_T\)\(PV_BUF \+ \(int\)\(BV_EO[LF]\)\)  :\n[ \t]*return \(char_u \*\)&\(curbuf->b_p_eo[lf]\);\n',
        '', "get_varp handing out 'endofline' and 'endoffile'", 2))
    # b_no_eol_lnum recorded the unterminated last line for a 'binary' write.
    # readfile() no longer sets it, and these two resets are all that is left.
    t = subn(t, r'^[ \t]*curbuf->b_no_eol_lnum = 0;\n', '', "resetting the no-LF line for 'binary'", 2)
    t = in_function(t, 'set_init_1', lambda s: literal(
        s, '    save_file_ff(curbuf);\n\n', '', 'startup saving the format of the first buffer'))
    t = in_function(t, 'did_set_modified', lambda s: drop_if(
        s, r'^[ \t]*if \(!args->os_newval\.boolean\)$', "'nomodified' saving the format"))
    def cpi(s):
        s = fold(s, r'^[ \t]*if \(get_fileformat\(curbuf\) == EOL_DOS\)$', 'g CTRL-G counting CR LF as two bytes')
        s = fold(s, r'^[ \t]*if \(lnum == curbuf->b_ml\.ml_line_count && !curbuf->b_p_eol && \(curbuf->b_p_bin \|\| !curbuf->b_p_fixeol\) && [^\n]*\)$',
                 'g CTRL-G at a last line with no LF')
        s = fold(s, r'^[ \t]*if \(!curbuf->b_p_eol && \(curbuf->b_p_bin \|\| !curbuf->b_p_fixeol\)\)$', 'g CTRL-G counting a missing last LF')
        return s
    t = in_function(t, 'cursor_pos_info', cpi)
    def unch(s):
        s = literal(s, 'buf->b_changed || (ff && file_ff_differs(buf, FALSE))', 'buf->b_changed', 'a changed format counting as a change')
        s = drop_if(s, r'^[ \t]*if \(ff\)$', 'unchanged saving the format')
        return s
    t = in_function(t, 'unchanged', unch)
    t = in_function(t, 'bufIsChangedNotTerm', lambda s: literal(
        s, '(buf->b_changed || file_ff_differs(buf, TRUE))', '(buf->b_changed)', 'a changed format counting as changed'))
    t = in_function(t, 'buf_clear_file', lambda s: subn(
        s, r'^[ \t]*buf->b_(?:p|start)_eo[fl] = (?:FALSE|TRUE);\n', '', "buf_clear_file resetting 'endofline' and 'endoffile'", 4))
    t = in_function(t, 'transchar_nonprint', lambda s: fold(
        s, r'^[ \t]*else if \(buf != NULL && c == CAR && get_fileformat\(buf\) == EOL_MAC\)$', 'CR shown as a line end'))
    t = in_function(t, 'do_ascii', lambda s: fold(
        s, r'^[ \t]*if \(c == CAR && get_fileformat\(curbuf\) == EOL_MAC\)$', 'ga showing CR as a line end'))
    t = in_function(t, 'ml_open', lambda s: subn(
        s, r'^[ \t]*b0p-> b0_fname\[B0_FNAME_SIZE_ORG - 2\]  = get_fileformat\(buf\) \+ 1;\n', '', 'block 0 recording the format'))
    t = in_function(t, 'ml_setflags', lambda s: subn(
        s, r'^[ \t]*b0p-> b0_fname\[B0_FNAME_SIZE_ORG - 2\]  = \(b0p-> b0_fname\[B0_FNAME_SIZE_ORG - 2\]  & ~B0_FF_MASK\)\n'
           r'[ \t]*\| \(get_fileformat\(buf\) \+ 1\);\n', '', 'block 0 updating the format'))
    t = in_function(t, 'set_init_3', lambda s: drop_if(
        s, r'^[ \t]*if \( \(curbuf->b_ml\.ml_line_count == 1 && \*ml_get\(\(linenr_T\)1\) == NUL\) \)$',
        "startup applying 'fileformats' to an empty buffer"))
    def argopt(s):
        s = drop_if(s, r'^[ \t]*if \( strncmp\(\(char \*\)\(arg\), \(char \*\)\("bin"\), \(3\)\)  == 0 \|\|  strncmp\(\(char \*\)\(arg\), \(char \*\)\("nobin"\), \(5\)\)  == 0\)$',
                    '++bin and ++nobin')
        s = fold(s, r'^[ \t]*if \( strncmp\(\(char \*\)\(arg\), \(char \*\)\("ff"\), \(2\)\)  == 0\)$', '++ff')
        s = fold(s, r'^[ \t]*if \( strncmp\(\(char \*\)\(arg\), \(char \*\)\("fileformat"\), \(10\)\)  == 0\)$', '++fileformat')
        s = fold(s, r'^[ \t]*if \(pp == &eap->force_ff\)$', '++ff checking its value')
        return s
    t = in_function(t, 'getargopt', argopt)
    t = in_function(t, 'prepare_help_buffer', lambda s: literal(
        s, '    curbuf->b_p_bin = FALSE;\n', '', "the help buffer clearing 'binary'"))
    def bco(s):
        a = s.index('switch (*p_ffs)')
        a = s.rindex('\n', 0, a) + 1
        b = cutil.blank(s)
        o = b.index('{', a)
        c = cutil.match(s, o, b)
        s = s[:a] + s[s.index('\n', c) + 1:]
        print("  lfonly       a new buffer's 'fileformat' from 'fileformats'")
        s = drop_if(s, r'^[ \t]*if \(buf->b_p_ff != NULL\)$', "a new buffer's remembered format")
        s = subn(s, r'^[ \t]*buf->b_p_(?:tw|wm|et)_nobin = p_(?:tw|wm|et)_nobin;\n', '', "a new buffer's values saved for 'binary'", 3)
        return s
    t = in_function(t, 'buf_copy_options', bco)

    # Every call left must be inside code the sweep takes with them: the format
    # functions themselves and the option callbacks whose rows whim50.sh drops.
    # Counted by where each call sits, not by a tally that has to be guessed.
    dying = ('get_fileformat', 'get_fileformat_force', 'set_fileformat', 'default_fileformat',
             'file_ff_differs', 'save_file_ff', 'set_file_options', 'set_options_bin',
             'msg_add_fileformat', 'check_ff_value', 'did_set_binary', 'did_set_fileformat',
             'did_set_fileformats', 'did_set_textmode', 'did_set_textauto', 'did_set_eof_eol_fixeol_bomb')
    spans = [sp for sp in (cutil.find_definition(t, n) for n in dying) if sp]
    heads = [(m.start(), m.group(1)) for m in re.finditer(r'^(\w+)\([^;\n]*\)[ \t]*\n\{', t, re.M)]
    live = []
    for n in dying:
        for m in re.finditer(r'\b%s\(' % n, t):
            line = t[t.rfind('\n', 0, m.start()) + 1:t.find('\n', m.start())]
            if line.startswith('static ') or re.match(r'%s\(' % n, line):
                continue
            if any(a <= m.start() < z for a, z in spans):
                continue
            owner = [h for s0, h in heads if s0 <= m.start()]
            live.append('%s in %s' % (n, owner[-1] if owner else '?'))
    if live:
        sys.exit('lfonly: still called from live code: %s' % ', '.join(live))

    path.write_text(t, errors='surrogateescape')
    print('  lfonly       every line ends with LF, read and written')


if __name__ == '__main__':
    main()
