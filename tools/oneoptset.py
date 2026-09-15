#!/usr/bin/env python3
"""One set of options: no :setlocal, no :setglobal, no :set opt<, and no modelines.

Usage:
    python3 tools/oneoptset.py <file>

Every buffer and window option still has two copies inside the editor, a global
one and a local one, and the storage stays: collapsing it would touch every
option's reader for nothing a user can see.  What goes is every way to make the
two copies DIFFER, so that :set -- which writes both -- is the only way an option
is ever given a value, and there is one set of options as far as anything outside
can tell.  Four things made them differ:

  :setlocal AND :setglobal wrote one copy each.  tools/retire.py points the rows
  at ex_ni; ex_set() stops choosing a flag for them, and their completion arms go.

  :set opt< copied the global copy into the local one.  The `<` suffix is no
  longer accepted, and the three branches that applied it -- boolean, number,
  string -- fold.  `:set ts<` is an error now, like any other malformed :set.

  MODELINES set a file's local copy from a `vim: set ...:` line in the file.  The
  four calls of do_modelines() go, so the sweep takes it and chk_modeline(); every
  test of OPT_MODELINE, a flag nothing passes once chk_modeline() is gone, folds;
  and 'modeline''s save and restore around 'binary' in set_options_bin() goes, so
  whim49.sh can drop the four modeline options and their fields.

Left alone: a value detected from the file being read -- 'fileformat', and
'binary' from -b -- is the current file's state, and with one buffer it is only
ever the one file's.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def literal(seg, old, new, what, count=1):
    n = seg.count(old)
    if n != count:
        sys.exit('oneoptset: %s -- occurs %d times, expected %d' % (what, n, count))
    print('  oneoptset    %s' % what)
    return seg.replace(old, new)


def subn(seg, pattern, new, what, count=1):
    seg, n = re.subn(pattern, new, seg, flags=re.M)
    if n != count:
        sys.exit('oneoptset: %s -- matched %d times, expected %d' % (what, n, count))
    print('  oneoptset    %s' % what)
    return seg


def fold(seg, pattern, what, count=1):
    try:
        seg = cutil.fold_never(seg, pattern, count, re.M)
    except ValueError as e:
        sys.exit('oneoptset: %s -- %s' % (what, e))
    print('  oneoptset    %s' % what)
    return seg


def drop_if(seg, pattern, what):
    n = len(re.findall(pattern, seg, re.M))
    if n != 1:
        sys.exit('oneoptset: %s -- the condition occurs %d times, expected 1' % (what, n))
    try:
        seg = cutil.drop_if(seg, pattern, flags=re.M)
    except ValueError as e:
        sys.exit('oneoptset: %s -- %s' % (what, e))
    print('  oneoptset    %s' % what)
    return seg


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        sys.exit('oneoptset: %s is not defined at file scope' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    t = path.read_text(errors='surrogateescape')

    # --- :setlocal and :setglobal -------------------------------------------------
    def exset(s):
        s = fold(s, r'^[ \t]*if \(eap->cmdidx == CMD_setlocal\)$', ':setlocal choosing OPT_LOCAL')
        s = fold(s, r'^[ \t]*if \(eap->cmdidx == CMD_setglobal\)$', ':setglobal choosing OPT_GLOBAL')
        return s
    t = in_function(t, 'ex_set', exset)
    t = in_function(t, 'set_context_by_cmdname', lambda s: subn(
        s, r'^[ \t]*case CMD_setglobal:\n[ \t]*set_context_in_set_cmd\(xp, arg, OPT_GLOBAL\);\n[ \t]*break;\n'
           r'[ \t]*case CMD_setlocal:\n[ \t]*set_context_in_set_cmd\(xp, arg, OPT_LOCAL\);\n[ \t]*break;\n',
        '', 'completion for :setglobal and :setlocal'))

    # --- :set opt< -------------------------------------------------------------------
    t = in_function(t, 'do_set_option', lambda s: literal(
        s, '(char_u *)"?=:!&<"', '(char_u *)"?=:!&"', ':set accepting the < suffix'))
    for name, kind in (('do_set_option_bool', 'a boolean'), ('do_set_option_numeric', 'a number'),
                       ('stropt_get_newval', 'a string')):
        t = in_function(t, name, lambda s, kind=kind: fold(
            s, r"^[ \t]*else if \(nextchar == '<'\)$", ':set opt< copying the global value of %s' % kind))

    # --- modelines -----------------------------------------------------------------------
    t = in_function(t, 'open_buffer', lambda s: literal(
        s, '            do_modelines(0);\n', '', 'reading a buffer applying its modelines'))
    t = in_function(t, 'do_write', lambda s: drop_if(
        s, r'^[ \t]*if \(\*curbuf->b_p_ft == NUL\)$', ':saveas applying modelines'))
    t = in_function(t, 'do_ecmd', lambda s: literal(
        s, '            do_modelines(OPT_WINONLY);\n\n', '', 'editing a file applying its window modelines'))
    t = in_function(t, 'set_rw_fname', lambda s: drop_if(
        s, r'^[ \t]*if \(\*curbuf->b_p_ft == NUL\)$', 'naming a buffer applying modelines'))
    t = in_function(t, 'validate_opt_idx', lambda s: fold(
        s, r'^[ \t]*if \(opt_flags & OPT_MODELINE\)$', 'the options a modeline may not set'))
    t = in_function(t, 'do_set', lambda s: literal(
        s, ' && !(opt_flags & OPT_MODELINE)', '', ':set all and :set termcap refused in a modeline', 2))
    t = in_function(t, 'do_set_option_string', lambda s: literal(
        s, '(opt_flags & OPT_MODELINE) || ', '', 'a modeline string option run securely'))
    t = in_function(t, 'did_set_option', lambda s: literal(
        s, '(secure || (opt_flags & OPT_MODELINE))', 'secure', 'a modeline value marked insecure'))
    t = in_function(t, 'do_filetype_autocmd', lambda s: fold(
        s, r'^[ \t]*if \(\(opt_flags & OPT_MODELINE\) && !value_changed\)$', "a modeline's unchanged 'filetype'"))
    t = in_function(t, 'set_options_bin', lambda s: subn(
        s, r'^[ \t]*(?:curbuf->b_p_ml(?:_nobin)?|p_ml(?:_nobin)?) = [^;\n]*;\n', '',
        "'binary' saving and restoring 'modeline'", 6))
    # b_p_ml_nobin is where 'binary' kept 'modeline' while it was off.  It is not
    # an option, so it has no get_varp() case and tools/droplocal.py does not know
    # its shape: its declaration and its one copy go here, and p_ml_nobin, with no
    # reader left, goes to the sweep.
    t = subn(t, r'^[ \t]*int[ \t]+b_p_ml_nobin;\n', '', "the buffer's saved 'modeline' field")
    t = in_function(t, 'buf_copy_options', lambda s: subn(
        s, r'^[ \t]*buf->b_p_ml_nobin = p_ml_nobin;\n', '', "a new buffer copying the saved 'modeline'"))

    dying = [cutil.find_definition(t, n) for n in ('chk_modeline', 'do_modelines')]
    n = len([m for m in re.finditer(r'\bOPT_MODELINE\b', t)
             if not any(sp and sp[0] <= m.start() < sp[1] for sp in dying)])
    if n != 1:
        sys.exit('oneoptset: OPT_MODELINE outside its enumerator and the dying modeline code -- %d, expected 1' % n)
    if len(re.findall(r'\bdo_modelines\(', t)) != 2:
        sys.exit('oneoptset: do_modelines is still called')

    path.write_text(t, errors='surrogateescape')
    print('  oneoptset    :set is the only way to give an option a value')


if __name__ == '__main__':
    main()
