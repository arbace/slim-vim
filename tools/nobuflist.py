#!/usr/bin/env python3
"""The buffer list is walked by :bnext and :bprevious, and by nothing else.

Usage:
    python3 tools/nobuflist.py <file>

The list itself stays: every file edited is a buffer on it, :bnext and
:bprevious move through it, CTRL-^ goes to the alternate one, and quitting still
asks about the changed ones.  tools/retire.py points the other rows at ex_ni;
this removes what a row cannot:

  :badd AND :balt went through ex_edit() and do_exedit() with :edit, so only
  their terms go -- and do_ecmd()'s ECMD_ADDBUF and ECMD_ALTBUF paths, which
  nothing else asked for.

  :bdelete, :bwipeout AND :bunload were do_bufdel() and do_buffer(), which the
  sweep takes.  That leaves do_buffer_ext() one caller, goto_buffer(), and one
  action, DOBUF_GOTO, so its `unload` is false and every branch that unloaded,
  deleted or wiped folds.  do_one_cmd() stops asking whether a buffer-name
  argument belongs to one of them.  set_curbuf() and empty_curbuf() keep their
  unload paths: check_changed_any() still passes one.

  :bNext is a row of its own, spelled apart from :bprevious though it shares the
  handler, so :bN goes with it; :bp still reaches :bprevious.

  COMPLETION for the retired names.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def literal(seg, old, new, what, count=1):
    n = seg.count(old)
    if n != count:
        sys.exit('nobuflist: %s -- occurs %d times, expected %d' % (what, n, count))
    print('  nobuflist    %s' % what)
    return seg.replace(old, new)


def subn(seg, pattern, new, what, count=1):
    seg, n = re.subn(pattern, new, seg, flags=re.M)
    if n != count:
        sys.exit('nobuflist: %s -- matched %d times, expected %d' % (what, n, count))
    print('  nobuflist    %s' % what)
    return seg


def fold(seg, kind, pattern, what, count=1):
    try:
        seg = (cutil.fold_never if kind == 'never' else cutil.fold_always)(seg, pattern, count, re.M)
    except ValueError as e:
        sys.exit('nobuflist: %s -- %s' % (what, e))
    print('  nobuflist    %s' % what)
    return seg


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        sys.exit('nobuflist: %s is not defined at file scope' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    t = path.read_text(errors='surrogateescape')

    # --- :badd and :balt ------------------------------------------------------------
    t = in_function(t, 'ex_edit', lambda s: literal(
        s, 'eap->cmdidx != CMD_badd && eap->cmdidx != CMD_balt && ', '', ':edit asking whether it was :badd or :balt'))
    def exedit(s):
        s = fold(s, 'always', r'^[ \t]*if \(eap->cmdidx != CMD_balt && eap->cmdidx != CMD_badd\)$',
                 'do_exedit setting the pcmark for :badd and :balt')
        s = literal(s, ' + (eap->cmdidx == CMD_badd ? ECMD_ADDBUF : 0) + (eap->cmdidx == CMD_balt ? ECMD_ALTBUF : 0)',
                    '', 'do_exedit passing ECMD_ADDBUF and ECMD_ALTBUF')
        return s
    t = in_function(t, 'do_exedit', exedit)
    def ecmd(s):
        s = fold(s, 'never', r'^[ \t]*if \(\(flags & \(ECMD_ADDBUF \| ECMD_ALTBUF\)\) && \(ffname == NULL \|\| \*ffname == NUL\)\)$',
                 'do_ecmd adding a buffer with no name')
        s = literal(s, '(ECMD_HIDE | ECMD_ADDBUF | ECMD_ALTBUF)', '(ECMD_HIDE)', 'do_ecmd sparing an added buffer the changed check')
        s = fold(s, 'always', r'^[ \t]*if \(!\(flags & \(ECMD_ADDBUF \| ECMD_ALTBUF\)\)\)$', 'do_ecmd keeping the alternate file')
        s = fold(s, 'never', r'^[ \t]*if \(flags & \(ECMD_ADDBUF \| ECMD_ALTBUF\)\)$', 'do_ecmd adding a buffer without editing it')
        s = literal(s, '(flags & (ECMD_ADDBUF | ECMD_ALTBUF)) || ', '', 'do_ecmd stopping after an added buffer')
        return s
    t = in_function(t, 'do_ecmd', ecmd)

    # --- :bdelete, :bwipeout, :bunload -------------------------------------------------
    t = in_function(t, 'do_one_cmd', lambda s: fold(
        s, 'never', r'^[ \t]*if \(ea\.cmdidx == CMD_bdelete \|\| ea\.cmdidx == CMD_bwipeout \|\| ea\.cmdidx == CMD_bunload\)$',
        'do_one_cmd reading a buffer list argument'))
    def dobuf(s):
        s = literal(s, '    int         unload = (action == DOBUF_UNLOAD || action == DOBUF_DEL || action == DOBUF_WIPE || action == DOBUF_WIPE_REUSE);\n',
                    '', 'do_buffer_ext deciding whether it unloads')
        s = literal(s, ' && !unload && ', ' && ', 'do_buffer_ext counting unlisted buffers for an unload')
        s = literal(s, '(unload || (help_only ? ', '((help_only ? ', 'do_buffer_ext counting every buffer for an unload')
        s = fold(s, 'always', r'^[ \t]*if \(!unload\)$', 'do_buffer_ext reporting a missing buffer')
        s = fold(s, 'never', r'^[ \t]*if \(unload\)$', 'do_buffer_ext unloading, deleting and wiping')
        if re.search(r'\bunload\b', s):
            sys.exit('nobuflist: do_buffer_ext still names unload')
        return s
    t = in_function(t, 'do_buffer_ext', dobuf)

    # --- :bNext -------------------------------------------------------------------------
    t = in_function(t, 'goto_buffer', lambda s: subn(s, r'^[ \t]*case CMD_bNext:\n', '', 'goto_buffer naming :bNext'))

    # --- completion ---------------------------------------------------------------------
    def complete(s):
        s = subn(s, r'^[ \t]*case CMD_bufdo:\n', '', 'completion for :bufdo')
        s = subn(s, r'^[ \t]*case CMD_bdelete:\n[ \t]*case CMD_bwipeout:\n[ \t]*case CMD_bunload:\n'
                    r"[ \t]*while \(\(xp->xp_pattern = vim_strchr\(arg, ' '\)\) != NULL\)\n"
                    r'[ \t]*\{\n[ \t]*arg = xp->xp_pattern \+ 1;\n[ \t]*\}\n[ \t]*__attribute__\(\(fallthrough\)\);\n',
                 '', 'completion for :bdelete, :bwipeout and :bunload')
        s = subn(s, r'^[ \t]*case CMD_buffer:\n', '', 'completion for :buffer')
        return s
    t = in_function(t, 'set_context_by_cmdname', complete)

    # Only the flags can be counted here.  ex_listdo() and ex_bunload() still name
    # CMD_bufdo and CMD_bdelete, and have no row now: the sweep takes them, and
    # whim41.sh counts the command names after it.
    n = len(re.findall(r'\bECMD_(ADDBUF|ALTBUF)\b', t))
    if n != 2:
        sys.exit('nobuflist: ECMD_ADDBUF or ECMD_ALTBUF outside their enumerators -- %d mentions, expected 2' % n)

    path.write_text(t, errors='surrogateescape')
    print('  nobuflist    only :bnext and :bprevious walk the buffer list')


if __name__ == '__main__':
    main()
