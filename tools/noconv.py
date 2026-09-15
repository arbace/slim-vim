#!/usr/bin/env python3
"""No conversion layer: a file is read and written as the UTF-8 bytes it holds.

Usage:
    python3 tools/noconv.py <file>

Phase 12 cut the conversion layer at its entry points and left its body: the
latin1, UCS-2, UTF-16 and UCS-4 read loops, the retry that tried the next
encoding, the byte-order-mark handling, the write-side conversion buffers, and
'encoding' itself, which accepts only utf-8.  Two ways in were still open:
++enc on :e, :r and :w, and a buffer with 'buftype' help, which readfile() read
as latin1-or-utf-8.  This closes both, and then everything behind them has one
answer:

  WITH ++enc AND THE HELP BRANCH GONE, fenc IS ALWAYS "".  need_conversion("") is
  false, so `converted` is; fio_flags is never set; iconv_fd, tmpname and
  fenc_next never change; can_retry is false.  Every test of them folds, in
  readfile() and buf_write(), and buf_write_bytes()'s conversion, which only a
  nonzero write flag reached, goes.  The BOM block did nothing: check_for_bom()
  has answered "no BOM" since Phase 12.  The rewind_retry block in the UTF-8
  check was reachable only through can_retry, and its label with it.

  'encoding' GOES.  Its row does in whim53.sh; here, mb_init() stops asking
  p_enc -- first, because a NULL p_enc was its "no multibyte" branch, and a row
  dropped before that fold would have switched UTF-8 off -- and
  set_options_default() stops skipping it.

  THE mb_* FUNCTION POINTERS ARE CALLS.  mb_init() pointed all ten at the UTF-8
  implementations every time; each call through one is a direct call now, the
  pointers and their latin1 initialisers go, and the sweep takes the latin1
  functions.  mb_tail_off() lost its DBCS test in Phase 52 and kept two dead
  returns after its last live one; they go, and dbcs_head_off() with them.

  NOR IS THE TERMINAL CONVERTED.  input_conv and output_conv, and the vimconv
  utf_find_illegal() and mb_init() set up, were CONV_NONE whenever 'encoding' was
  utf-8, and 'termencoding' went in Phase 12.  Their tests fold, and so does
  fill_input_buf()'s leftover from a conversion, which only convert_input_safe()
  set.  THIS IS NOT TIDYING: the only assignment of input_conv.vc_factor was in
  mb_init()'s no-encoding branch, folded above, and fill_input_buf() divides by
  it.  A first run of this phase that folded one and not the other built an
  editor that would divide by zero on its first read of input.

  COMPLETION for ++ff, ++fileformat, ++enc, ++encoding and ++bad, left behind by
  Phases 50 and 51 and this one, goes from expand_argopt() and get_argopt_name().
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

POINTERS = {
    'mb_ptr2len': 'utfc_ptr2len', 'mb_ptr2len_len': 'utfc_ptr2len_len', 'mb_char2len': 'utf_char2len',
    'mb_char2bytes': 'utf_char2bytes', 'mb_ptr2cells': 'utf_ptr2cells', 'mb_ptr2cells_len': 'utf_ptr2cells_len',
    'mb_char2cells': 'utf_char2cells', 'mb_off2cells': 'utf_off2cells', 'mb_ptr2char': 'utf_ptr2char',
    'mb_head_off': 'utf_head_off',
}


def die(msg, seg):
    dump = __import__('os').environ.get('NOCONV_DUMP')
    if dump:
        Path(dump).write_text(seg, errors='surrogateescape')
    sys.exit('noconv: ' + msg)


def literal(seg, old, new, what, count=1):
    n = seg.count(old)
    if n != count:
        die('%s -- occurs %d times, expected %d' % (what, n, count), seg)
    print('  noconv       %s' % what)
    return seg.replace(old, new)


def subn(seg, pattern, new, what, count=1, flags=re.M):
    seg, n = re.subn(pattern, new, seg, flags=flags)
    if n != count:
        die('%s -- matched %d times, expected %d' % (what, n, count), seg)
    print('  noconv       %s' % what)
    return seg


def fold(seg, pattern, what, kind='never', count=None):
    n = len(re.findall(pattern, seg, re.M)) if count is None else count
    if n == 0:
        die('%s -- no occurrence' % what, seg)
    try:
        for _ in range(n):
            # One at a time, from the last: a condition can repeat inside its own block.
            last = list(re.finditer(pattern, seg, re.M))[-1]
            start = seg.rfind('\n', 0, last.start()) + 1
            f = cutil.fold_never if kind == 'never' else cutil.fold_always
            seg = seg[:start] + f(seg[start:], pattern, 1, re.M)
    except (ValueError, IndexError) as e:
        die('%s -- %s' % (what, e), seg)
    print('  noconv       %s%s' % (what, '' if n == 1 else ' (%d)' % n))
    return seg


def drop_if(seg, pattern, what):
    n = len(re.findall(pattern, seg, re.M))
    if n != 1:
        die('%s -- the condition occurs %d times, expected 1' % (what, n), seg)
    try:
        seg = cutil.drop_if(seg, pattern, flags=re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e), seg)
    print('  noconv       %s' % what)
    return seg


def keep_then(seg, pattern, what):
    """An `if (T) { A } else { B }` whose condition is always true: keep A, lose B."""
    ms = list(re.finditer(pattern, seg, re.M))
    if len(ms) != 1:
        die('%s -- the condition occurs %d times, expected 1' % (what, len(ms)), seg)
    b = cutil.blank(seg)
    k, o, c, head = cutil._guarded(seg, ms[0], b)
    if head != 'if':
        die('%s -- not a plain if' % what, seg)
    end = seg.index('\n', c) + 1
    rest = seg[end:]
    nxt = re.match(r'[ \t]*else\b', rest)
    if not nxt or re.match(r'[ \t]*else[ \t]+if\b', rest):
        die('%s -- expected a plain else after the block' % what, seg)
    o2 = b.index('{', end + nxt.end())
    c2 = cutil.match(seg, o2, b)
    body = cutil._dedent4(seg[seg.index('\n', o) + 1:seg.rfind('\n', 0, c) + 1])
    print('  noconv       %s' % what)
    return seg[:k] + body + seg[seg.index('\n', c2) + 1:]


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        sys.exit('noconv: %s is not defined at file scope' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    t = path.read_text(errors='surrogateescape')

    # --- ++enc ----------------------------------------------------------------------
    def argopt(s):
        s = drop_if(s, r'^[ \t]*if \( strncmp\(\(char \*\)\(arg\), \(char \*\)\("enc"\), \(3\)\)  == 0\)$', '++enc and ++encoding')
        s = subn(s, r"^    if \(pp == NULL \|\| \*arg != '='\)\n.*?^    return OK;\n", '    return FAIL;\n',
                 'getargopt: every ++ argument but ++edit is unknown', flags=re.M | re.S)
        return s
    t = in_function(t, 'getargopt', argopt)

    # --- readfile ---------------------------------------------------------------------
    def read(s):
        s = subn(s, r'^[ \t]*if \(eap != NULL\)\n[ \t]*\{\n[ \t]*set_forced_fenc\(eap\);\n[ \t]*\}\n', '',
                 'a new file taking ++enc')
        s = fold(s, r'^[ \t]*if \(eap != NULL && eap->force_enc != 0\)$', 'readfile honouring ++enc')
        s = fold(s, r'^[ \t]*if \(curbuf->b_help\)$', 'a help buffer read as latin1 or utf-8')
        s = fold(s, r'^[ \t]*if \(advance_fenc\)$', 'readfile moving to the next encoding')
        s = subn(s, r'^[ \t]*converted = need_conversion\(fenc\);\n', '', 'readfile asking whether to convert')
        s = fold(s, r'^[ \t]*if \(converted\)$', 'readfile choosing a conversion')
        s = subn(s, r'^[ \t]*can_retry = \(\*fenc != NUL && !read_stdin && !read_fifo && !keep_dest_enc\);\n\n', '',
                 'readfile deciding it may retry')
        s = fold(s, r'^[ \t]*if \(fio_flags != 0\)$', 'the latin1, UCS-2, UTF-16 and UCS-4 read loops')
        s = fold(s, r'^[ \t]*if \(fio_flags != 0 \|\| iconv_fd != \(iconv_t\)-1\)$', 'an incomplete converted tail')
        s = fold(s, r'^[ \t]*if \(iconv_fd != \(iconv_t\)-1\)$', 'reading room for iconv')
        for flag in (r'fio_flags & FIO_LATIN1', r'fio_flags & \(FIO_UCS2 \| FIO_UTF16\)', r'fio_flags & FIO_UCS4',
                     r'fio_flags == FIO_UCSBOM'):
            s = fold(s, r'^[ \t]*if \(%s\)$' % flag, 'reading room for a %s' % flag.replace('\\', ''))
        s = drop_if(s, r"^[ \t]*if \(\(filesize == 0\) && \(fio_flags == FIO_UCSBOM \|\| \(tmpname == NULL && \(\*fenc == 'u' \|\| \(\*fenc == NUL\)\)\)\)\)$",
                    'the byte-order-mark check, which finds none')
        s = fold(s, r'^[ \t]*if \(iconv_fd != \(iconv_t\)-1 && conv_error == 0\)$', 'an iconv error in the UTF-8 check')
        s = fold(s, r'^[ \t]*if \(can_retry && !incomplete_tail\)$', 'the UTF-8 check stopping to retry')
        s = drop_if(s, r'^[ \t]*if \(p < ptr \+ size && !incomplete_tail\)$', 'the rewind to retry another encoding')
        s = literal(s, 'if (conv_error == 0 && illegal_byte == 0)', 'if (illegal_byte == 0)', 'an illegal byte deferring to a conversion error')
        s = fold(s, r'^[ \t]*if \(file_rewind\)$', 'readfile rewinding for a retry')
        if 'goto retry' in s:
            sys.exit('noconv: readfile still jumps to retry')
        s = subn(s, r'^retry:\n\n', '', 'the retry label')
        s = fold(s, r'^[ \t]*if \(tmpname != NULL\)$', "'charconvert''s temporary file")
        s = fold(s, r'^[ \t]*if \(fenc_alloced\)$', 'readfile freeing an encoding name')
        s = fold(s, r'^[ \t]*if \(notconverted\)$', 'the "[NOT converted]" message')
        s = fold(s, r'^[ \t]*if \(converted\)$', 'the "[converted]" message')
        s = fold(s, r'^[ \t]*if \(conv_error != 0\)$', 'the "[CONVERSION ERROR]" message')
        if 'goto failed' in s:
            die('readfile still jumps to failed', s)
        s = subn(s, r'^failed:\n', '', 'the failed label, which only a rewind jumped to')
        s = literal(s, 'if (newfile && (error || conv_error != 0))', 'if (newfile && error)', 'a conversion error making the buffer read-only')
        s = subn(s, r'^[ \t]*fio_flags = 0;\n', '', 'readfile clearing the conversion flags', 2)
        s = subn(s, r'^[ \t]*fenc = \(char_u \*\)"";\n', '', 'readfile setting the empty encoding')
        s = subn(s, r'^[ \t]*fenc_alloced = FALSE;\n', '', 'readfile noting it owns no encoding name')
        s = subn(s, r'^[ \t]*real_size = \(int\)size;\n', '', "readfile remembering the converted buffer's size")
        return s
    t = in_function(t, 'readfile', read)

    # --- buf_write ------------------------------------------------------------------------
    def write(s):
        s = fold(s, r'^[ \t]*if \(eap != NULL && eap->force_enc != 0\)$', 'buf_write honouring ++enc')
        s = subn(s, r'^[ \t]*fenc = \(char_u \*\)"";\n', '', 'buf_write setting the empty encoding')
        s = subn(s, r'^[ \t]*converted = need_conversion\(fenc\);\n\n', '', 'buf_write asking whether to convert')
        s = fold(s, r'^[ \t]*if \(converted\)$', 'buf_write allocating conversion buffers')
        s = fold(s, r'^[ \t]*if \(converted && wb_flags == 0 && write_info\.bw_iconv_fd == \(iconv_t\)-1\)$',
                 'buf_write refusing a conversion it cannot do')
        s = fold(s, r'^[ \t]*if \(!converted\)$', 'buf_write skipping the conversion check', kind='always')
        s = fold(s, r'^[ \t]*else if \(notconverted\)$', 'the "[NOT converted]" write message')
        s = fold(s, r'^[ \t]*else if \(converted\)$', 'the "[converted]" write message')
        s = subn(s, r'^[ \t]*vim_free\(fenc_tofree\);\n', '', "buf_write freeing ++enc's name")
        # Only buf_write_bytes()'s conversion set bw_conv_error, and it has gone.
        s = fold(s, r'^[ \t]*if \(write_info\.bw_conv_error\)$', 'a conversion error in a write', count=2)
        s = literal(s, ' && !write_info.bw_conv_error && ', ' && ', 'a conversion error keeping the buffer modified')
        # The pass that only checked a conversion is never taken: the loop body clears
        # the flag before its first test.
        s = fold(s, r'^[ \t]*if \(checking_conversion\)$', 'buf_write checking a conversion without writing')
        s = fold(s, r'^[ \t]*if \(!checking_conversion\)$', 'buf_write syncing after the pass that wrote', kind='always')
        s = subn(s, r'^[ \t]*write_info\.bw_conv_buf = NULL;\n', '', 'buf_write clearing the conversion buffer')
        s = subn(s, r'^[ \t]*vim_free\(write_info\.bw_conv_buf\);\n', '', 'buf_write freeing the conversion buffer')
        return s
    t = in_function(t, 'buf_write', write)
    t = in_function(t, 'buf_write_bytes', lambda s: drop_if(
        s, r'^[ \t]*if \(!\(flags & FIO_NOCONVERT\)\)$', 'buf_write_bytes converting, which no write flag asks for'))
    t = in_function(t, 'do_ecmd', lambda s: subn(
        s, r'^[ \t]*if \(!oldbuf && eap != NULL\)\n[ \t]*\{\n[ \t]*set_forced_fenc\(eap\);\n[ \t]*\}\n', '',
        'editing a file taking ++enc'))

    # --- 'encoding' -------------------------------------------------------------------------
    def mbinit(s):
        s = fold(s, r'^[ \t]*if \(p_enc == NULL\)$', 'mb_init without an encoding')
        s = fold(s, r'^[ \t]*if \( strcmp\(\(char \*\)\(p_enc\), \(char \*\)\("utf-8"\)\)  != 0\)$', 'mb_init refusing another encoding')
        s = subn(s, r'^[ \t]*mb_\w+ = utf\w+;\n', '', 'mb_init pointing the mb_* functions at UTF-8', 10)
        s = subn(s, r'^[ \t]*vimconv_T[ \t]+vimconv;\n', '', "mb_init's conversion")
        s = subn(s, r'^[ \t]*vimconv\.vc_type = CONV_NONE;\n', '', 'mb_init clearing a conversion')
        s = subn(s, r'^[ \t]*convert_setup\(&vimconv, NULL, NULL\);\n', '', 'mb_init setting up no conversion')
        s = subn(s, r'^for \(i = 0; i < 256; \+\+i\)$', '    for (i = 0; i < 256; ++i)', "mb_init's byte-length loop, indented")
        return s
    t = in_function(t, 'mb_init', mbinit)
    # THE BRANCH FOLDED ABOVE WAS TAKEN, ONCE.  common_init_1() calls mb_init()
    # before any option exists, and p_enc NULL sent that call to the 1s and back;
    # set_init_1() makes the real call later.  Without the branch the first call
    # ran on into init_chartab() with no curbuf, and the editor crashed before its
    # first command.  The first call is what it did then.
    t = in_function(t, 'common_init_1', lambda s: literal(
        s, '    (void)mb_init();\n', '    for (int i = 0; i < 256; ++i)\n    {\n        mb_bytelen_tab[i] = 1;\n    }\n',
        'startup filling the byte lengths before any option exists'))
    t = in_function(t, 'set_options_default', lambda s: literal(
        s, ' && (opt_flags == 0 || (options[i].var != (char_u *)&p_enc))', '', "setting defaults skipping 'encoding'"))

    # --- the terminal ---------------------------------------------------------------------
    def illegal(s):
        s = fold(s, r'^[ \t]*if \(vimconv\.vc_type != CONV_NONE\)$', ':ga-style search converting a line first')
        s = keep_then(s, r'^[ \t]*if \(vimconv\.vc_type == CONV_NONE\)$', 'the illegal byte found in the line itself')
        s = subn(s, r'^[ \t]*vimconv_T[ \t]+vimconv;\n', '', "utf_find_illegal's conversion")
        s = subn(s, r'^[ \t]*char_u[ \t]+\*tofree = NULL;\n', '', "utf_find_illegal's converted copy")
        s = subn(s, r'^[ \t]*vimconv\.vc_type = CONV_NONE;\n\n', '', 'utf_find_illegal clearing a conversion')
        s = subn(s, r'^[ \t]*vim_free\(tofree\);\n', '', 'utf_find_illegal freeing a converted copy')
        s = subn(s, r'^[ \t]*convert_setup\(&vimconv, NULL, NULL\);\n', '', 'utf_find_illegal ending no conversion')
        return s
    t = in_function(t, 'utf_find_illegal', illegal)
    t = in_function(t, 'ui_write', lambda s: fold(
        s, r'^[ \t]*if \(output_conv\.vc_type != CONV_NONE\)$', 'output converted for the terminal', count=2))

    def inbuf(s):
        s = literal(s, '((INBUFLEN - inbufcount) / input_conv.vc_factor)', '(INBUFLEN - inbufcount)',
                    'input read in room for a conversion to grow')
        s = fold(s, r'^[ \t]*if \(input_conv\.vc_type != CONV_NONE\)$', 'input converted from the terminal')
        s = fold(s, r'^[ \t]*if \(rest != NULL\)$', 'input left over from a conversion')
        s = subn(s, r'^[ \t]*unconverted = 0;\n', '', 'nothing left unconverted')
        return s
    t = in_function(t, 'fill_input_buf', inbuf)

    # --- the mb_* pointers become calls -------------------------------------------------------
    t = subn(t, r'^static int \(\*mb_\w+\)\([^;\n]*\)\s*=\s*latin_\w+\s*;\n', '', 'the mb_* function pointers', 10)
    calls = 0
    for ptr, fn in POINTERS.items():
        t, a = re.subn(r'\(\*%s\)\(' % ptr, fn + '(', t)
        t, b = re.subn(r'(?<![\w*])%s\(' % ptr, fn + '(', t)
        calls += a + b
        if re.search(r'\b%s\b' % ptr, t):
            sys.exit('noconv: %s is still named after its calls were made direct' % ptr)
    print('  noconv       %d calls through an mb_* pointer are direct calls' % calls)
    t = in_function(t, 'mb_tail_off', lambda s: literal(
        s, '    return i;\n\n    return 0;\n\n    return 1 - dbcs_head_off(base, p);\n', '    return i;\n',
        "mb_tail_off's dead DBCS returns"))

    # --- completion ----------------------------------------------------------------------------
    def argexp(s):
        link = r'^[ \t]*if \(name_end - xp->xp_line >= \d+ &&  strncmp\(\(char \*\)\(name_end - \d+\), \(char \*\)\("\w+"\), \(\d+\)\)  == 0\)$'
        for _ in range(5):
            s = fold(s, link, 'completion for an ++ argument value', count=1)
        s = fold(s, r'^[ \t]*if \(cb != NULL\)$', 'completing an ++ argument value')
        s = drop_if(s, r'^[ \t]*if \(xp->xp_pattern_len == 2 &&  strncmp\(\(char \*\)\(xp->xp_pattern\), \(char \*\)\("ff"\), \(xp->xp_pattern_len\)\)  == 0\)$',
                    'completing ++ff to ++fileformat=')
        return s
    t = in_function(t, 'expand_argopt', argexp)
    t = in_function(t, 'get_argopt_name', lambda s: subn(
        s, r'^[ \t]*"(?:fileformat=|encoding=|nobinary|bad=)",\n', '', 'the ++ff, ++enc, ++nobin and ++bad names', 4))

    path.write_text(t, errors='surrogateescape')
    print('  noconv       a file is read and written as the UTF-8 bytes it holds')


if __name__ == '__main__':
    main()
