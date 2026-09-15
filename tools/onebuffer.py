#!/usr/bin/env python3
"""One buffer, always: editing another file reuses it, and nothing remembers the last.

Usage:
    python3 tools/onebuffer.py <file>

The buffer list stays -- firstbuf, curbuf and the hash table are the container
the editor edits in -- with exactly one buffer on it between commands.  Editing
another file still goes through do_ecmd(), which makes the new buffer and then
closes the old one; what changes is that the old one is WIPED, the way
'bufhidden=wipe' always did it, instead of being unloaded and kept on the list
or hidden with its changes.  So :e, :enew, :next, :previous, :drop and gf work as
before, and a file left behind takes its undo history, marks and local options
with it.  tools/retire.py points :bnext, :bprevious and :keepalt at ex_ni; this
removes what a row cannot:

  NOTHING IS HIDDEN.  buf_hide() answered from 'hidden', the :hide modifier and
  'bufhidden', and all three go -- so every one of its callers folds as if it
  said no, and close_buffer() stops reading 'bufhidden'.  :hide {cmd} is
  unknown now, and whim42.sh drops 'hidden' and 'bufhidden'.

  THE OLD BUFFER IS WIPED.  do_ecmd() closed it with DOBUF_UNLOAD, or not at all
  under ECMD_HIDE; it closes it with DOBUF_WIPE.  Changes cannot be lost by it:
  do_ecmd() has already refused a changed buffer unless it was written or ! was
  given, exactly as it did with 'nohidden'.

  NO ALTERNATE FILE.  The alternate is itself a second buffer.  Nothing writes
  w_alt_fnum: do_ecmd(), set_curbuf(), do_exedit() and win_init() stop, :file
  and :read and :write stop making an alternate buffer for a name, and
  buflist_findnr(0) and a '#' buffer pattern find nothing, which is what they
  did when there was no alternate.  CTRL-^ points at nv_error, and :keepalt
  has nothing to keep.

  :saveas RENAMED THE BUFFER BY SWAPPING NAMES WITH AN ALTERNATE BUFFER made for
  the new name.  With no alternate it would write the file and keep the old name,
  so it renames the one buffer with setfname() instead -- the only line here that
  is not a cut, and the reason is that the mechanism, not the behaviour, needed
  a second buffer.

  THE ARGUMENT LIST STOPS MAKING BUFFERS.  alist_add() put every file argument on
  the buffer list, unloaded, the moment it was named.  An entry is a name now,
  with buffer number 0 -- alist_name() and editing_arg_idx() already fall back to
  the name -- and the one buffer is named for the first file only while it is
  still the empty buffer startup made, as before.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def literal(seg, old, new, what, count=1):
    n = seg.count(old)
    if n != count:
        sys.exit('onebuffer: %s -- occurs %d times, expected %d' % (what, n, count))
    print('  onebuffer    %s' % what)
    return seg.replace(old, new)


def subn(seg, pattern, new, what, count=1, flags=re.M):
    seg, n = re.subn(pattern, new, seg, flags=flags)
    if n != count:
        sys.exit('onebuffer: %s -- matched %d times, expected %d' % (what, n, count))
    print('  onebuffer    %s' % what)
    return seg


def fold(seg, pattern, what, count=1):
    try:
        seg = cutil.fold_never(seg, pattern, count, re.M)
    except ValueError as e:
        sys.exit('onebuffer: %s -- %s' % (what, e))
    print('  onebuffer    %s' % what)
    return seg


def drop_if(seg, pattern, what):
    n = len(re.findall(pattern, seg, re.M))
    if n != 1:
        sys.exit('onebuffer: %s -- the condition occurs %d times, expected 1' % (what, n))
    try:
        seg = cutil.drop_if(seg, pattern, flags=re.M)
    except ValueError as e:
        sys.exit('onebuffer: %s -- %s' % (what, e))
    print('  onebuffer    %s' % what)
    return seg


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        sys.exit('onebuffer: %s is not defined at file scope' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    t = path.read_text(errors='surrogateescape')

    # --- the modifiers ------------------------------------------------------------
    def mods(s):
        s = subn(s, r"^[ \t]*case 'h':\n[ \t]*if \(p != eap->cmd \|\| !checkforcmd_noparen\(&p, \"hide\", 3\) \|\| \*p == NUL \|\| ends_excmd\(\*p\)\)\n"
                    r'[ \t]*\{\n[ \t]*break;\n[ \t]*\}\n[ \t]*eap->cmd = p;\n[ \t]*cmod->cmod_flags \|= CMOD_HIDE;\n[ \t]*continue;\n\n',
                 '', 'the :hide modifier')
        s = drop_if(s, r'^[ \t]*if \(checkforcmd_noparen\(&eap->cmd, "keepalt", 5\)\)$', 'the :keepalt modifier')
        return s
    t = in_function(t, 'parse_command_modifiers', mods)
    t = in_function(t, 'set_context_by_cmdname', lambda s: subn(
        s, r'^[ \t]*case CMD_(?:hide|keepalt):\n', '', 'completion for :hide and :keepalt', 2))

    # --- nothing is hidden: every caller of buf_hide() hears no -------------------------
    def argfile(s):
        s = fold(s, r'^[ \t]*if \(buf_hide\(curbuf\)\)$', 'do_argfile asking whether the file is another')
        s = literal(s, '(!buf_hide(curbuf) || !other) && ', '', 'do_argfile checking a hidden buffer')
        s = literal(s, '(other ? 0 : CCGD_MULTWIN) | ', '', 'do_argfile checking the same file in two windows')
        s = subn(s, r'^[ \t]*other = TRUE;\n', '', 'do_argfile assuming another file')
        s = literal(s, '(buf_hide(curwin->w_buffer) ? ECMD_HIDE : 0) + ', '', 'do_argfile hiding the buffer')
        return s
    t = in_function(t, 'do_argfile', argfile)
    t = in_function(t, 'ex_next', lambda s: literal(s, '(       buf_hide(curbuf) || ', '(', ':next hiding the buffer'))
    t = in_function(t, 'set_curbuf', lambda s: literal(s, '!buf_hide(prevbuf) && ', '', 'set_curbuf hiding the buffer'))
    def getfile(s):
        s = literal(s, ' && !buf_hide(curbuf) && ', ' && ', 'getfile writing before it leaves')
        s = literal(s, '(buf_hide(curbuf) ? ECMD_HIDE : 0) + ', '', 'getfile hiding the buffer')
        return s
    t = in_function(t, 'getfile', getfile)
    t = in_function(t, 'can_abandon', lambda s: literal(s, '(       buf_hide(buf) || ', '(', 'can_abandon a hidden buffer'))
    def quit(s):
        s = literal(s, '(!buf_hide(wp->w_buffer) && check_changed(', '(check_changed(', ':quit sparing a hidden buffer')
        s = literal(s, 'win_close(wp, !buf_hide(wp->w_buffer) || eap->forceit)', 'win_close(wp, TRUE)', ':quit freeing the buffer')
        return s
    t = in_function(t, 'ex_quit', quit)
    t = in_function(t, 'ex_exit', lambda s: literal(
        s, 'win_close(curwin, !buf_hide(curwin->w_buffer))', 'win_close(curwin, TRUE)', ':exit freeing the buffer'))
    def exedit(s):
        s = literal(s, '(buf_hide(curbuf) ? ECMD_HIDE : 0) + ', '', ':edit hiding the buffer')
        s = literal(s, 'if (!need_hide || buf_hide(curbuf))', 'if (!need_hide)', ':edit closing a failed window')
        s = literal(s, '!need_hide && !buf_hide(curbuf)', '!need_hide', ':edit freeing a failed window')
        s = drop_if(s, r'^[ \t]*if \(old_curwin != NULL && \*eap->arg != NUL && curwin != old_curwin && win_valid\(old_curwin\) && '
                       r'old_curwin->w_buffer != curbuf && \(cmdmod\.cmod_flags & CMOD_KEEPALT\) == 0\)$',
                    ':edit leaving an alternate in the old window')
        return s
    t = in_function(t, 'do_exedit', exedit)
    def gotofile(s):
        s = literal(s, ' && !buf_hide(curbuf))', ')', 'gf refusing a changed buffer')
        s = literal(s, 'buf_hide(curbuf) ? ECMD_HIDE : 0', '0', 'gf hiding the buffer')
        return s
    t = in_function(t, 'nv_gotofile', gotofile)
    if len(re.findall(r'\bbuf_hide\(', t)) != 2:
        sys.exit('onebuffer: buf_hide is still called -- %d mentions, expected its prototype and definition'
                 % len(re.findall(r'\bbuf_hide\(', t)))

    # --- 'bufhidden' ------------------------------------------------------------------------
    def close(s):
        s = fold(s, r"^[ \t]*if \(buf->b_p_bh\[0\] == 'd'\)$", "close_buffer's bufhidden=delete")
        s = fold(s, r"^[ \t]*if \(buf->b_p_bh\[0\] == 'w'\)$", "close_buffer's bufhidden=wipe")
        s = fold(s, r"^[ \t]*if \(buf->b_p_bh\[0\] == 'u'\)$", "close_buffer's bufhidden=unload")
        return s
    t = in_function(t, 'close_buffer', close)

    # --- the old buffer is wiped ----------------------------------------------------------------
    def ecmd(s):
        s = literal(s, '(flags & ECMD_HIDE) ? 0 : DOBUF_UNLOAD', 'DOBUF_WIPE', 'do_ecmd wiping the buffer it leaves')
        s = drop_if(s, r'^[ \t]*if \(fnum == 0 && other_file && ffname != NULL\)$', 'do_ecmd naming a refused file the alternate')
        s = literal(s, '        int prev_alt_fnum = curwin->w_alt_fnum;\n\n', '', 'do_ecmd remembering the alternate')
        s = drop_if(s, r'^[ \t]*if \(\(cmdmod\.cmod_flags & CMOD_KEEPALT\) == 0\)$', 'do_ecmd making the old buffer the alternate')
        s = subn(s, r'^[ \t]*if \(oldwin != NULL\)\n[ \t]*\{\n[ \t]*buflist_altfpos\(oldwin\);\n[ \t]*\}\n', '',
                 'do_ecmd saving the old window position')
        s = drop_if(s, r'^[ \t]*if \(curwin->w_alt_fnum == buf->b_fnum && prev_alt_fnum != 0\)$', 'do_ecmd restoring the alternate')
        return s
    t = in_function(t, 'do_ecmd', ecmd)

    # --- no alternate file -----------------------------------------------------------------------
    def curbuf_(s):
        s = drop_if(s, r'^[ \t]*if \(\(cmdmod\.cmod_flags & CMOD_KEEPALT\) == 0\)$', 'set_curbuf making the old buffer the alternate')
        s = subn(s, r'^[ \t]*buflist_altfpos\(curwin\);\n', '', 'set_curbuf saving the window position')
        return s
    t = in_function(t, 'set_curbuf', curbuf_)
    def rename(s):
        s = drop_if(s, r'^[ \t]*if \(xfname != NULL && \*xfname != NUL\)$', ':file keeping the old name as the alternate')
        # xfname held the old short name for that alternate alone.
        s = literal(s, '    char_u *xfname;\n', '', ':file declaring the old short name')
        s = literal(s, '    xfname = curbuf->b_fname;\n', '', ':file saving the old short name')
        return s
    t = in_function(t, 'rename_buffer', rename)
    t = in_function(t, 'win_init', lambda s: literal(
        s, '    newp->w_alt_fnum = oldp->w_alt_fnum;\n', '', 'win_init copying the alternate'))
    t = in_function(t, 'ex_read', lambda s: drop_if(
        s, r'^[ \t]*if \(vim_strchr\(p_cpo, CPO_ALTREAD\) != NULL\)$', ':read naming the alternate'))
    t = in_function(t, 'buflist_findnr', lambda s: drop_if(
        s, r'^[ \t]*if \(nr == 0\)$', 'buffer 0 meaning the alternate'))
    t = in_function(t, 'buflist_findpat', lambda s: literal(
        s, 'match = curwin->w_alt_fnum;', 'match = 0;', "'#' finding the alternate"))
    t = subn(t, r'^([ \t]*\{Ctrl_HAT, )nv_hat(, NV_NCW, 0\} ,)$', r'\1nv_error\2', "CTRL-^'s row points at nv_error")

    def write(s):
        s = drop_if(s, r'^    if \(other\)$', ':write making the written name the alternate')
        s = subn(s, r'^        if \(eap->cmdidx == CMD_saveas && alt_buf != NULL\)\n        \{\n.*?\n'
                    r'            fname = curbuf->b_sfname;\n        \}\n',
                 '        if (eap->cmdidx == CMD_saveas)\n'
                 '        {\n'
                 '            if (setfname(curbuf, ffname, fname, TRUE) == FAIL)\n'
                 '            {\n'
                 '                goto theend;\n'
                 '            }\n'
                 '            if (*curbuf->b_p_ft == NUL)\n'
                 '            {\n'
                 '                do_modelines(0);\n'
                 '            }\n'
                 '            fname = curbuf->b_sfname;\n'
                 '        }\n',
                 ':saveas renaming the one buffer instead of swapping names with another', flags=re.M | re.S)
        return s
    t = in_function(t, 'do_write', write)

    # --- the argument list stops making buffers -------------------------------------------------------
    t = in_function(t, 'alist_add', lambda s: subn(
        s, r'^([ \t]*)if \(set_fnum > 0\)\n[ \t]*\{\n([ \t]*\(\(aentry_T \*\)\(\(al\)->al_ga\.ga_data\)\) \[al->al_ga\.ga_len\]\.ae_fnum =)\n'
           r'[ \t]*buflist_add\(fname, BLN_LISTED \| \(set_fnum == 2 \? BLN_CURBUF : 0\)\);\n[ \t]*\}\n',
        r'\2 0;\n\1if (set_fnum == 2 && curbuf_reusable())\n\1{\n\2\n\1        buflist_add(fname, BLN_LISTED | BLN_CURBUF);\n\1}\n',
        'an argument naming a buffer only when it is the empty startup one'))
    def addlist(s):
        s = subn(s, r'^[ \t]*int flags = BLN_LISTED \| \(will_edit \? BLN_CURBUF : 0\);\n\n', '', 'alist_add_list choosing buffer flags')
        s = literal(s, '.ae_fnum = buflist_add(files[i], flags);', '.ae_fnum = 0;', 'alist_add_list making a buffer per argument')
        return s
    t = in_function(t, 'alist_add_list', addlist)

    # setaltfname() and buf_hide() have no caller now and still name the
    # alternate and the two modifier flags; the sweep takes them, and whim42.sh
    # counts again after it.  Everything else is counted here.
    dying = [cutil.find_definition(t, n) for n in ('setaltfname', 'buf_hide')]
    def count(pattern):
        return len([m for m in re.finditer(pattern, t)
                    if not any(sp and sp[0] <= m.start() < sp[1] for sp in dying)])
    left = [(what, n) for what, pattern, want in (
                ('w_alt_fnum outside its field', r'\bw_alt_fnum\b', 1),
                ('CMOD_KEEPALT or CMOD_HIDE outside their enumerators', r'\bCMOD_(?:KEEPALT|HIDE)\b', 2),
                ('buflist_altfpos called', r'\bbuflist_altfpos\(curwin\)|\bbuflist_altfpos\(oldwin\)', 0),
                ('nv_hat in the key table', r'\{Ctrl_HAT, nv_hat', 0))
            for n in [count(pattern)] if n != want]
    if left:
        sys.exit('onebuffer: still present: %s' % left)

    path.write_text(t, errors='surrogateescape')
    print('  onebuffer    one buffer: the old one is wiped, nothing is hidden, nothing is the alternate')


if __name__ == '__main__':
    main()
