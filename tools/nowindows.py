#!/usr/bin/env python3
"""One window, always, and nothing that makes, reaches, resizes or binds another.

Usage:
    python3 tools/nowindows.py <file>

The window list is the container the editor draws into -- `firstwin`, `curwin`
and the frame tree are read everywhere, and aucmd_prepbuf() still slots its
hidden autocommand window into the layout with win_split_ins() -- so it stays,
with exactly one user window.  tools/retire.py points the rows at ex_ni; this
removes what a row cannot:

  THE MODIFIERS.  :aboveleft, :leftabove, :belowright, :rightbelow, :topleft,
  :botright, :vertical and :horizontal are matched by name in
  parse_command_modifiers(), before the table, and were all that set
  cmdmod.cmod_split.  :hide {cmd} is a modifier too and stays.

  THE KEY.  CTRL-W's row points at nv_error, as a row is never deleted, and every
  window command behind it goes with do_window().

  THE COMMAND-LINE WINDOW, which is a split.  q: q/ q? become the recordings they
  would be without it (and beep, those registers not being recordable), CTRL-F on
  the command line is an ordinary key, and every question asked of cmdwin_type,
  cmdwin_win, cmdwin_buf and cmdwin_result is answered: none is open.

  -o AND -O become unknown options, and startup opens no window per file.

  THE PATHS THAT STILL SPLIT.  :drop's fallback when the buffer cannot be
  abandoned, do_argfile()'s 's' commands, goto_buffer()'s :sb* family, and
  buflist_getfile()'s 'switchbuf' block.  :drop now does what :first does: it
  refuses to abandon a modified buffer.

  THE OPTIONS WHOSE READERS GO HERE.  'scrollbind' and 'cursorbind' bind one
  window to another; 'winfixbuf' is answered by splitting.  Their tests fold,
  their assignments and plumbing go, and whim39.sh drops the rows.  'switchbuf',
  'scrollopt', 'cmdwinheight' and 'cedit' lose their last reader here too.
  The sizing options -- 'winheight', 'winminheight', 'splitbelow' and the rest --
  are still read by the frame arithmetic aucmd_prepbuf() uses, and are Phase 40.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil
import dropopts


def literal(seg, old, new, what, count=1):
    n = seg.count(old)
    if n != count:
        sys.exit('nowindows: %s -- occurs %d times, expected %d' % (what, n, count))
    print('  nowindows    %s' % what)
    return seg.replace(old, new)


def subn(seg, pattern, new, what, count=1):
    seg, n = re.subn(pattern, new, seg, flags=re.M)
    if n != count:
        sys.exit('nowindows: %s -- matched %d times, expected %d' % (what, n, count))
    print('  nowindows    %s' % what)
    return seg


def fold(seg, pattern, what, count=1):
    try:
        seg = cutil.fold_never(seg, pattern, count, re.M)
    except ValueError as e:
        sys.exit('nowindows: %s -- %s' % (what, e))
    print('  nowindows    %s' % what)
    return seg


def drop_if(seg, pattern, what):
    try:
        seg = cutil.drop_if(seg, pattern, flags=re.M)
    except ValueError as e:
        sys.exit('nowindows: %s -- %s' % (what, e))
    print('  nowindows    %s' % what)
    return seg


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        sys.exit('nowindows: %s is not defined at file scope' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    t = path.read_text(errors='surrogateescape')

    # --- the modifiers ----------------------------------------------------------
    B = r'[ \t]*\{\n[ \t]*break;\n[ \t]*\}\n'
    def mods(s):
        s = subn(s, r"^[ \t]*case 'a':\n[ \t]*if \(!checkforcmd_noparen\(&eap->cmd, \"aboveleft\", 3\)\)\n" + B +
                 r'[ \t]*cmod->cmod_split \|= WSP_ABOVE;\n[ \t]*continue;\n\n', '', ':aboveleft')
        s = subn(s, r"^[ \t]*case 'b':\n[ \t]*if \(checkforcmd_noparen\(&eap->cmd, \"belowright\", 3\)\)\n"
                    r'[ \t]*\{\n[ \t]*cmod->cmod_split \|= WSP_BELOW;\n[ \t]*continue;\n[ \t]*\}\n'
                    r'[ \t]*if \(!checkforcmd_noparen\(&eap->cmd, "botright", 2\)\)\n' + B +
                 r'[ \t]*cmod->cmod_split \|= WSP_BOT;\n[ \t]*continue;\n\n', '', ':belowright and :botright')
        s = subn(s, r'^[ \t]*if \(checkforcmd_noparen\(&eap->cmd, "horizontal", 3\)\)\n'
                    r'[ \t]*\{\n[ \t]*cmod->cmod_split \|= WSP_HOR;\n[ \t]*continue;\n[ \t]*\}\n', '', ':horizontal')
        s = subn(s, r'^([ \t]*)if \(!checkforcmd_noparen\(&eap->cmd, "leftabove", 5\)\)\n' + B +
                 r'[ \t]*cmod->cmod_split \|= WSP_ABOVE;\n[ \t]*continue;\n', r'\1break;\n', ':leftabove')
        s = subn(s, r"^[ \t]*case 'r':\n[ \t]*if \(!checkforcmd_noparen\(&eap->cmd, \"rightbelow\", 6\)\)\n" + B +
                 r'[ \t]*cmod->cmod_split \|= WSP_BELOW;\n[ \t]*continue;\n\n', '', ':rightbelow')
        s = subn(s, r"^[ \t]*case 't':\n[ \t]*if \(!checkforcmd_noparen\(&eap->cmd, \"topleft\", 2\)\)\n" + B +
                 r'[ \t]*cmod->cmod_split \|= WSP_TOP;\n[ \t]*continue;\n\n', '', ':topleft')
        s = subn(s, r'^[ \t]*if \(checkforcmd_noparen\(&eap->cmd, "vertical", 4\)\)\n'
                    r'[ \t]*\{\n[ \t]*cmod->cmod_split \|= WSP_VERT;\n[ \t]*continue;\n[ \t]*\}\n', '', ':vertical')
        return s
    t = in_function(t, 'parse_command_modifiers', mods)
    t = in_function(t, 'has_cmdmod', lambda s: literal(
        s, '            || cmod->cmod_split != 0\n', '', 'has_cmdmod counting a split modifier'))

    # --- the key ------------------------------------------------------------------
    t = subn(t, r'^([ \t]*\{Ctrl_W, )nv_window(, 0, 0\} ,)$', r'\1nv_error\2', "CTRL-W's row points at nv_error")

    # --- the command-line window ---------------------------------------------------
    t = in_function(t, 'nv_record', lambda s: fold(
        s, r"^[ \t]*if \(cap->nchar == ':' \|\| cap->nchar == '/' \|\| cap->nchar == '\?'\)$", 'q: q/ q? opening it'))
    t = in_function(t, 'getcmdline_int', lambda s: fold(
        s, r'^[ \t]*if \(c == cedit_key \|\| c == [^\n]*KE_CMDWIN[^\n]*\)$', 'CTRL-F on the command line opening it'))
    plain = r'^[ \t]*if \(cmdwin_type != 0\)$'
    for name in ('ex_quit', 'before_quit_all', 'ex_exit', 'text_locked', 'get_text_locked_msg',
                 'nv_normal'):
        t = in_function(t, name, lambda s, name=name: fold(s, plain, '%s asking whether it is open' % name))
    def edit(s):
        s = fold(s, r'^[ \t]*if \(c == Ctrl_C && cmdwin_type != 0\)$', 'insert-mode CTRL-C closing it')
        s = fold(s, plain, 'insert-mode Enter executing it')
        s = fold(s, r'^[ \t]*if \(curwin-> w_onebuf_opt\.wo_scb \)$', "insert mode's 'scrollbind'")
        s = fold(s, r'^[ \t]*if \(curwin-> w_onebuf_opt\.wo_crb \)$', "insert mode's 'cursorbind'")
        return s
    t = in_function(t, 'edit', edit)
    t = in_function(t, 'do_one_cmd', lambda s: fold(
        s, r'^[ \t]*if \(cmdwin_type != 0 && !\(ea\.argt & EX_CMDWIN\)\)$', 'commands refused inside it'))
    t = in_function(t, 'goto_tabpage_tp', lambda s: drop_if(
        s, r'^[ \t]*if \(trigger_enter_autocmds \|\| trigger_leave_autocmds\)$', 'goto_tabpage_tp refusing inside it'))
    t = in_function(t, 'nv_down', lambda s: fold(
        s, r'^[ \t]*if \(cmdwin_type != 0 && cap->cmdchar == CAR\)$', 'normal-mode Enter executing it'))
    def esc(s):
        s = literal(s, 'cmdwin_type == 0 && ', '', 'nv_esc asking before the abandon hint')
        s = fold(s, plain, 'normal-mode Esc closing it')
        s = fold(s, r'^[ \t]*else if \(cmdwin_type != 0 && ex_normal_busy && typebuf_was_empty\)$', ':normal Esc closing it')
        return s
    t = in_function(t, 'nv_esc', esc)
    def vget(s):
        s = literal(s, ' || (cmdwin_type > 0 && tc == ESC)', '', 'an interrupted Esc closing it')
        # tc remembered the previous key for that test alone.
        s = literal(s, '                    static int tc = 0;\n', '', 'vgetorpeek declaring the previous key')
        s = literal(s, '                    tc = c;\n', '', 'vgetorpeek remembering it')
        return s
    t = in_function(t, 'vgetorpeek', vget)
    def ecmd(s):
        s = literal(s, '            int         save_cmdwin_type = cmdwin_type;\n'
                       '            win_T       *save_cmdwin_win = cmdwin_win;\n\n'
                       '            cmdwin_type = 0;\n            cmdwin_win = NULL;\n', '', 'do_ecmd hiding it')
        s = literal(s, '            cmdwin_type = save_cmdwin_type;\n            cmdwin_win = save_cmdwin_win;\n\n',
                    '', 'do_ecmd restoring it')
        return s
    t = in_function(t, 'do_ecmd', ecmd)
    t = in_function(t, 'win_line', lambda s: fold(s, r'^[ \t]*if \(wp == cmdwin_win\)$', 'its column drawn'))
    t = in_function(t, 'win_col_off', lambda s: literal(
        s, ' + (wp != cmdwin_win ? 0 : 1)', '', 'its column counted'))
    t = in_function(t, 'buf_spname', lambda s: fold(s, r'^[ \t]*if \(buf == cmdwin_buf\)$', 'its buffer name'))
    t = in_function(t, 'comp_textwidth', lambda s: fold(s, r'^[ \t]*if \(curbuf == cmdwin_buf\)$', 'its textwidth'))
    t = in_function(t, 'main_loop', lambda s: literal(
        s, 'while (!cmdwin || cmdwin_result == 0)', 'while (!cmdwin)', 'main_loop waiting for its result'))
    t = in_function(t, 'didset_options', lambda s: literal(
        s, '    (void)did_set_cedit(NULL);\n', '', "startup reading 'cedit'"))
    t = in_function(t, 'check_num_option_bounds', lambda s: drop_if(
        s, r'^[ \t]*if \(p_cwh < 1\)$', "'cmdwinheight' clamped"))

    # --- -o and -O ----------------------------------------------------------------
    def scan(s):
        s, held = dropopts.drop_short(s, 0, {'o', 'O'})
        if held != {'o', 'O'}:
            sys.exit('nowindows: -o and -O are not both labels in the option switch: %s' % sorted(held))
        print('  nowindows    -o and -O are unknown options')
        return s
    t = in_function(t, 'command_line_scan', scan)
    def create(s):
        s = drop_if(s, r'^[ \t]*if \(parmp->window_count == -1\)$', 'create_windows defaulting the count')
        s = drop_if(s, r'^[ \t]*if \(parmp->window_count == 0\)$', 'create_windows counting the files')
        s = fold(s, r'^[ \t]*if \(parmp->window_count > 1\)$', 'create_windows making a window per file')
        s = literal(s, '    parmp->window_count = 1;\n', '', 'create_windows settling on one')
        return s
    t = in_function(t, 'create_windows', create)
    t = subn(t, r'^[ \t]+edit_buffers\([^\n]*\);\n', '', 'startup editing a file in each window')
    t = literal(t, '    params.window_count = -1;\n', '', 'main initialising the window count')

    # --- 'scrollbind', 'cursorbind', 'winfixbuf': assignments and plumbing ---------
    t = subn(t, r'^[ \t]*\((?:curwin|wp)\)-> w_onebuf_opt\.wo_(?:scb|crb)  = FALSE;\n', '',
             "every assignment of 'scrollbind' and 'cursorbind'", 18)
    for wv, fld in (('SCBIND', 'scb'), ('CRBIND', 'crb'), ('WFB', 'wfb')):
        t = subn(t, r'^[ \t]*case   \(idopt_T\)\(PV_WIN \+ \(int\)\(WV_%s\)\)  :\n'
                    r'[ \t]*return \(char_u \*\)&\(curwin-> w_onebuf_opt\.wo_%s \);\n' % (wv, fld), '',
                 'get_varp for WV_%s' % wv)
    t = literal(t, '    to->wo_scb = from->wo_scb;\n    to->wo_scb_save = from->wo_scb_save;\n', '',
                "copy_winopt copying 'scrollbind'")
    t = literal(t, '    to->wo_crb = from->wo_crb;\n    to->wo_crb_save = from->wo_crb_save;\n', '',
                "copy_winopt copying 'cursorbind'")
    def normal(s):
        s = fold(s, r'^[ \t]*if \(curwin-> w_onebuf_opt\.wo_scb  && toplevel\)$', "normal mode's 'scrollbind'")
        s = fold(s, r'^[ \t]*if \(curwin-> w_onebuf_opt\.wo_crb  && toplevel\)$', "normal mode's 'cursorbind'")
        return s
    t = in_function(t, 'normal_cmd', normal)
    t = in_function(t, 'ex_substitute', lambda s: fold(
        s, r'^[ \t]*if \(curwin-> w_onebuf_opt\.wo_crb \)$', ":s's 'cursorbind'"))
    t = in_function(t, 'set_shellsize_inner', lambda s: fold(
        s, r'^[ \t]*if \(curwin-> w_onebuf_opt\.wo_scb \)$', "a resize's 'scrollbind'"))
    t = in_function(t, 'scroll_to_fraction', lambda s: literal(
        s, '(!wp-> w_onebuf_opt.wo_scb  || wp == curwin) && ', '', "scroll_to_fraction's 'scrollbind'"))
    for name in ('check_can_set_curbuf_disabled', 'check_can_set_curbuf_forceit'):
        t = in_function(t, name, lambda s, name=name: fold(
            s, r'^[ \t]*if \((?:!forceit && )?curwin-> w_onebuf_opt\.wo_wfb \)$', "%s's 'winfixbuf'" % name))

    # --- the paths that still split -----------------------------------------------------
    def drop(s):
        s = literal(s, '    int         split = FALSE;\n', '', ':drop declaring its fallback')
        s = drop_if(s, r'^[ \t]*if \(!buf_hide\(curbuf\)\)$', ':drop asking whether to split')
        s = fold(s, r'^[ \t]*if \(split\)$', ':drop splitting')
        return s
    t = in_function(t, 'ex_drop', drop)
    def argfile(s):
        s = literal(s, "    int is_split_cmd = *eap->cmd == 's';\n", '', 'do_argfile asking for a split')
        s = literal(s, '!is_split_cmd && ', '', 'do_argfile checking the buffer can go')
        s = fold(s, r'^[ \t]*if \(is_split_cmd\)$', 'do_argfile splitting')
        return s
    t = in_function(t, 'do_argfile', argfile)
    def gotobuf(s):
        s = subn(s, r'^[ \t]*case CMD_(?:sbnext|sbNext|sbprevious):\n', '', 'goto_buffer naming :sb commands', 3)
        s = literal(s, "*eap->cmd == 's' ? DOBUF_SPLIT : DOBUF_GOTO", 'DOBUF_GOTO', 'goto_buffer choosing a split')
        s = fold(s, r"^[ \t]*if \(swap_exists_action == SEA_QUIT && \*eap->cmd == 's'\)$", 'goto_buffer closing the split')
        return s
    t = in_function(t, 'goto_buffer', gotobuf)
    def dobuf(s):
        s = literal(s, '(action == DOBUF_GOTO || action == DOBUF_SPLIT)', 'action == DOBUF_GOTO',
                    'do_buffer_ext refusing a dummy buffer')
        s = fold(s, r'^[ \t]*if \(action == DOBUF_SPLIT && swbuf_goto_win_with_buf\(buf\) != NULL\)$',
                 "do_buffer_ext's 'switchbuf'")
        s = fold(s, r'^[ \t]*if \(action == DOBUF_SPLIT && win_split\(0, 0\) == FAIL\)$', 'do_buffer_ext splitting')
        s = fold(s, r'^[ \t]*if \(action == DOBUF_SPLIT\)$', 'do_buffer_ext unbinding the split')
        return s
    t = in_function(t, 'do_buffer_ext', dobuf)
    t = in_function(t, 'buflist_getfile', lambda s: drop_if(
        s, r'^[ \t]*if \(options & GETF_SWITCH\)$', "buflist_getfile's 'switchbuf'"))
    t = literal(t, '    (void)opt_strings_flags(p_swb, p_swb_values, &swb_flags, TRUE);\n', '',
                "didset_string_options reading 'switchbuf'")
    def listdo(s):
        s = fold(s, r'^[ \t]*if \(curwin-> w_onebuf_opt\.wo_wfb  && eap->cmdidx != CMD_windo\)$', "ex_listdo's 'winfixbuf'")
        s = literal(s, 'eap->cmdidx == CMD_windo || ', '', ':windo skipping the changed-buffer check')
        s = subn(s, r'^[ \t]*wp = firstwin;\n[ \t]*switch \(eap->cmdidx\)\n[ \t]*\{\n[ \t]*case CMD_windo:\n'
                    r'[ \t]*for \( ; wp != NULL && i \+ 1 < eap->line1; wp = wp->w_next\)\n[ \t]*\{\n[ \t]*i\+\+;\n'
                    r'[ \t]*\}\n[ \t]*break;\n[ \t]*default:\n[ \t]*break;\n[ \t]*\}\n', '', ":windo's starting window")
        s = fold(s, r'^[ \t]*if \(eap->cmdidx == CMD_windo\)$', ':windo stepping, binding and stopping', 3)
        s = literal(s, '    int         i;\n    win_T       *wp;\n', '', 'ex_listdo declaring its counters')
        s = literal(s, '        i = 0;\n', '', 'ex_listdo starting the count')
        s = literal(s, '            ++i;\n\n', '', 'ex_listdo counting')
        return s
    t = in_function(t, 'ex_listdo', listdo)
    t = in_function(t, 'set_context_by_cmdname', lambda s: subn(
        s, r'^[ \t]*case CMD_windo:\n', '', 'completion for :windo'))

    left = [(what, n) for what, pattern, want in (
                ('a split modifier in the parser', r'cmod->cmod_split \|=', 0),
                ('nv_window in the key table', r'\{Ctrl_W, nv_window', 0),
                ('DOBUF_SPLIT outside its enumerator', r'\bDOBUF_SPLIT\b', 1),
                ('CMD_windo outside the table', r'^(?![ \t]*\[?CMD_)[^\n]*\bCMD_windo\b', 0))
            for n in [len(re.findall(pattern, t, re.M))] if n != want]
    if left:
        sys.exit('nowindows: still present: %s' % left)

    path.write_text(t, errors='surrogateescape')
    print('  nowindows    nothing makes, reaches, resizes or binds a second window')


if __name__ == '__main__':
    main()
