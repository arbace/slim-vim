#!/usr/bin/env python3
"""No tab pages: one tab page, always, and nothing that makes or reaches another.

Usage:
    python3 tools/notabs.py <file>

The tab-page list is the container every window lives in -- `curtab` and
`first_tabpage` are read in hundreds of places -- so it stays, with exactly one
entry.  What goes is every way to make or reach a second one.  tools/retire.py
points the rows at ex_ni (:tab, :tabnew, :tabedit, :tabclose, :tabonly, :tabnext
and its family, :tabmove, :tabs, :tabdo, :redrawtabline); this removes what a row
cannot:

  THE MODIFIER.  `:tab` is matched by name in parse_command_modifiers(), before
  the table, and it was the only thing that set cmdmod.cmod_tab.  With it gone
  every test of cmod_tab is decided, and the tab branches of :all, :ball, :drop,
  :argedit and CTRL-W gf are folded.

  THE COMMANDS' SHARED HANDLERS.  :tabnew and :tabedit went through ex_splitview
  with :split and :new, and :tabdo through ex_listdo with :windo -- so only their
  terms and branches go, not the handlers.

  THE KEYS KEEP THEIR ONE-TAB-PAGE ANSWER.  With a single tab page, goto_tabpage(n)
  beeps when n > 1 and otherwise does nothing, and the last-used tab page never
  exists.  So `gt`, CTRL-PageDown and CTRL-W gt beep for a count above 1 and do
  nothing otherwise; `gT`, CTRL-PageUp and CTRL-W gT do nothing; g<Tab>, CTRL-Tab
  and CTRL-W g<Tab> beep; insert mode's CTRL-PageUp and CTRL-PageDown stay the
  no-ops they were.  That is what each already did -- the keys are not given a
  new meaning, they lose a function that could never be reached.  CTRL-W T (move
  the window to a new tab page) and CTRL-W gf (edit a file in a new one) beep, as
  an unknown window command does.

  THE TAB LINE.  tabline_height() is 0 and draw_tabline() draws nothing, which
  is what they returned for one tab page under the default 'showtabline'; the
  options that could change that go after the sweep.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def replace_body(text, name, new_body):
    span = cutil.find_definition(text, name)
    if not span:
        sys.exit('notabs: %s is not defined at file scope' % name)
    a, z = span
    seg = text[a:z]
    b = cutil.blank(seg)
    o = b.index('{')
    c = cutil.match(seg, o, b)
    return text[:a] + seg[:o] + '{\n' + new_body + '}' + seg[c + 1:] + text[z:]


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        sys.exit('notabs: %s is not defined at file scope' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


def literal(seg, old, new, what, count=1):
    n = seg.count(old)
    if n != count:
        sys.exit('notabs: %s -- occurs %d times, expected %d' % (what, n, count))
    print('  notabs       %s' % what)
    return seg.replace(old, new)


def fold(seg, kind, pattern, what, count=1):
    try:
        seg = (cutil.fold_never if kind == 'never' else cutil.fold_always)(seg, pattern, count, re.M)
    except ValueError as e:
        sys.exit('notabs: %s -- %s' % (what, e))
    print('  notabs       %s' % what)
    return seg


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    t = path.read_text(errors='surrogateescape')

    # --- the modifier ------------------------------------------------------
    pat = r'^[ \t]*if \(checkforcmd_noparen\(&p, "tab", 3\)\)$'
    if len(re.findall(pat, t, re.M)) != 1:
        sys.exit('notabs: the :tab modifier is not where this expects')
    t = cutil.drop_if(t, pat, flags=re.M)
    print('  notabs       the :tab modifier')

    # --- the doors that stay closed ----------------------------------------
    for name, body in (('tabline_height', '    return 0;\n'),
                       ('draw_tabline', '    redraw_tabline = FALSE;\n')):
        t = replace_body(t, name, body)
    print('  notabs       the tab line is 0 lines and draws nothing')
    # A stub answers the question; it does not remove the caller.  win_split()
    # asked may_open_tabpage() whether a :tab-modified split had become a tab
    # page, and nothing can modify one now -- so the question goes, and the
    # sweep takes the function.
    t = in_function(t, 'win_split', lambda s: fold(
        s, 'never', r'^[ \t]*if \(may_open_tabpage\(\) == OK\)$', 'win_split opening a tab page for :tab'))

    # --- cmod_tab, which nothing sets any more ------------------------------
    t = literal(t, 'is_split_cmd || cmdmod.cmod_tab != 0', 'is_split_cmd', ':argedit and friends testing for :tab')
    t = literal(t, '            || cmod->cmod_tab != 0\n', '', 'has_cmdmod counting :tab')
    t = literal(t, ' && cmdmod.cmod_tab == 0)', ')', "CTRL-W's 'switchbuf' test for :tab")
    t = literal(t, '    cmdmod.cmod_tab = 0;\n    cmdmod.cmod_flags |= CMOD_NOSWAPFILE;\n',
                '    cmdmod.cmod_flags |= CMOD_NOSWAPFILE;\n', 'the command-line window clearing :tab')
    t = fold(t, 'never', r'^[ \t]*if \(cmdmod\.cmod_tab\)$', ':drop under :tab')
    t = literal(t, '        postponed_split_tab = cmdmod.cmod_tab;\n', '', ':wincmd passing :tab on')
    t = literal(t, '        postponed_split_tab = 0;\n', '', ':wincmd clearing it')

    def ball(seg):
        seg = fold(seg, 'never', r'^[ \t]*if \(had_tab > 0\)$', ':ball starting at the first tab page')
        seg = literal(seg, ' || (had_tab > 0 && wp != firstwin))', ')', ':ball closing windows for tab pages')
        seg = fold(seg, 'always', r'^[ \t]*if \(had_tab == 0 \|\| tpnext == NULL\)$', ':ball stopping after one tab page')
        seg = fold(seg, 'never', r'^[ \t]*if \(had_tab != 0\)$', ':ball opening tab pages')
        seg = fold(seg, 'never', r'^[ \t]*if \(had_tab > 0 && tabpage_index\(NULL\) <= p_tpm\)$',
                   ":ball's 'tabpagemax'")
        seg = literal(seg, '    int         had_tab = cmdmod.cmod_tab;\n', '', ':ball remembering :tab')
        return seg
    t = in_function(t, 'ex_buffer_all', ball)

    def argall_close(seg):
        seg = fold(seg, 'never', r'^[ \t]*if \(aall->had_tab > 0\)$', ':all starting at the first tab page')
        seg = literal(seg, '(first_tabpage->tp_next == NULL || !aall->had_tab)', 'TRUE',
                      ':all deciding whether a last window may go')
        seg = fold(seg, 'always', r'^[ \t]*if \(aall->had_tab == 0 \|\| tpnext == NULL\)$',
                   ':all stopping after one tab page')
        return seg
    t = in_function(t, 'arg_all_close_unused_windows', argall_close)
    t = in_function(t, 'arg_all_open_windows', lambda s: fold(
        s, 'never', r'^[ \t]*if \(aall->had_tab > 0 && tabpage_index\(NULL\) <= p_tpm\)$', ":all's 'tabpagemax'"))
    t = literal(t, '    aall.had_tab = cmdmod.cmod_tab;\n', '', ':all remembering :tab')

    # --- the commands' shared handlers --------------------------------------
    def splitview(seg):
        seg = literal(seg, '''    int         use_tab = eap->cmdidx == CMD_tabedit
                       || eap->cmdidx == CMD_tabfind
                       || eap->cmdidx == CMD_tabnew;
''', '', 'ex_splitview asking whether this is a tab command')
        seg = fold(seg, 'never', r'^[ \t]*if \(use_tab\)$', 'ex_splitview opening a tab page')
        return seg
    t = in_function(t, 'ex_splitview', splitview)
    t = literal(t, ' || eap->cmdidx == CMD_tabnew || eap->cmdidx == CMD_tabedit || eap->cmdidx == CMD_vnew)',
                ' || eap->cmdidx == CMD_vnew)', ':tabnew and :tabedit with no file in do_exedit')
    t = fold(t, 'never', r'^[ \t]*if \(close_disallowed == 0 && cmd == CMD_tabnew\)$',
             'window_layout_locked naming :tabnew')

    def listdo(seg):
        seg = literal(seg, 'eap->cmdidx != CMD_windo && eap->cmdidx != CMD_tabdo)', 'eap->cmdidx != CMD_windo)',
                      ":tabdo in 'winfixbuf'")
        seg = literal(seg, 'eap->cmdidx == CMD_windo || eap->cmdidx == CMD_tabdo || buf_hide',
                      'eap->cmdidx == CMD_windo || buf_hide', ':tabdo needing no write')
        seg = literal(seg, '''            case CMD_tabdo:
                for ( ; tp != NULL && i + 1 < eap->line1; tp = tp->tp_next)
                {
                    i++;
                }
                break;
''', '', ':tabdo finding its first tab page')
        seg = fold(seg, 'never', r'^[ \t]*else if \(eap->cmdidx == CMD_tabdo\)$', ':tabdo moving to the next tab page')
        seg = literal(seg, 'if (eap->cmdidx == CMD_windo || eap->cmdidx == CMD_tabdo)', 'if (eap->cmdidx == CMD_windo)',
                      ':tabdo counting its range')
        # The tab-page cursor only :tabdo read.  Set and never read is a warning
        # the sweep does not act on, so it goes here.
        seg = literal(seg, '    tabpage_T   *tp;\n', '', ':tabdo\'s tab-page cursor')
        seg = literal(seg, '        tp = first_tabpage;\n', '', ':tabdo starting at the first tab page')
        if re.search(r'\btp\b', seg):
            sys.exit('notabs: ex_listdo still names tp after :tabdo went')
        return seg
    t = in_function(t, 'ex_listdo', listdo)

    # --- the keys ----------------------------------------------------------------
    def g_cmd(seg):
        seg = literal(seg, '''    case 't':
        if (!checkclearop(oap))
        {
            goto_tabpage((int)cap->count0);
        }
        break;
''', '''    case 't':
        if (!checkclearop(oap) && cap->count0 > 1)
        {
            beep_flush();
        }
        break;
''', 'gt: a count above 1 beeps, as with one tab page')
        seg = literal(seg, '''    case 'T':
        if (!checkclearop(oap))
        {
            goto_tabpage(-(int)cap->count1);
        }
        break;
''', '''    case 'T':
        (void)checkclearop(oap);
        break;
''', 'gT: nothing, as with one tab page')
        seg = literal(seg, 'if (!checkclearop(oap) && goto_tabpage_lastused() == FAIL)', 'if (!checkclearop(oap))',
                      'g<Tab>: beeps, there being no last-used tab page')
        return seg
    t = in_function(t, 'nv_g_cmd', g_cmd)
    t = in_function(t, 'nv_pcmark', lambda s: fold(
        s, 'always', r'^[ \t]*if \(goto_tabpage_lastused\(\) == FAIL\)$', 'CTRL-Tab: beeps'))
    t = in_function(t, 'nv_page', lambda s: literal(s, '''        if (cap->arg ==  (-1) )
        {
            goto_tabpage(-(int)cap->count1);
        }
        else
        {
            goto_tabpage((int)cap->count0);
        }
''', '''        if (cap->arg !=  (-1)  && cap->count0 > 1)
        {
            beep_flush();
        }
''', 'CTRL-PageUp and CTRL-PageDown: the one-tab-page answer'))
    for fn in ('ins_pageup', 'ins_pagedown'):
        t = in_function(t, fn, lambda s, fn=fn: fold(
            s, 'never', r'^[ \t]*if \(first_tabpage->tp_next != NULL\)$', '%s: no second tab page to reach' % fn))

    def window(seg):
        b = cutil.blank(seg)
        m = re.search(r"^    case 'T':\n", seg, re.M)
        if not m or len(re.findall(r"^    case 'T':\n", seg, re.M)) != 1:
            sys.exit("notabs: CTRL-W T is not where this expects")
        end = re.search(r"^    case 't':\n", seg[m.end():], re.M)
        if not end:
            sys.exit("notabs: CTRL-W T is not followed by CTRL-W t")
        block = seg[m.start():m.end() + end.start()]
        if 'win_new_tabpage' not in block:
            sys.exit('notabs: the CTRL-W T block does not open a tab page')
        seg = seg[:m.start()] + seg[m.end() + end.start():]
        print('  notabs       CTRL-W T: moving a window to a new tab page')
        seg = literal(seg, '''                    case 'f':
                    case 'F':
                        cmdmod.cmod_tab = tabpage_index(curtab) + 1;
                        nchar = xchar;
                        goto wingotofile;
''', '''                    case 'f':
                    case 'F':
                        beep_flush();
                        break;
''', 'CTRL-W gf and gF: editing a file in a new tab page')
        # CTRL-W gf was the only goto to it; CTRL-W f falls into the code directly.
        seg = literal(seg, 'wingotofile:\n', '', 'the label only CTRL-W gf jumped to')
        seg = literal(seg, '''                    case 't':
                        goto_tabpage((int)Prenum);
                        break;
''', '''                    case 't':
                        if (Prenum > 1)
                        {
                            beep_flush();
                        }
                        break;
''', 'CTRL-W gt: the one-tab-page answer')
        seg = literal(seg, '''                    case 'T':
                        goto_tabpage(-(int)Prenum1);
                        break;
''', '''                    case 'T':
                        break;
''', 'CTRL-W gT: the one-tab-page answer')
        seg = fold(seg, 'always', r'^[ \t]*if \(goto_tabpage_lastused\(\) == FAIL\)$', 'CTRL-W g<Tab>: beeps')
        return seg
    t = in_function(t, 'do_window', window)

    # --- 'tabclose', whose row goes before the sweep ---------------------------
    # With no row nothing sets tcl_flags, so it is 0 for ever: "use the last-used
    # tab page" is never asked for, and "go left" never is either.
    def alt(seg):
        seg = fold(seg, 'never', r'^[ \t]*if \(\(tcl_flags & TCL_USELAST\) && valid_tabpage\(lastused_tabpage\)\)$',
                   "alt_tabpage: 'tabclose' asking for the last-used tab page")
        seg = literal(seg, '''    forward = curtab->tp_next != NULL &&
            ((tcl_flags & TCL_LEFT) == 0 || curtab == first_tabpage);
''', '''    forward = curtab->tp_next != NULL;
''', "alt_tabpage: 'tabclose' asking to go left")
        return seg
    t = in_function(t, 'alt_tabpage', alt)

    # --- an option read at startup by name of its global ----------------------
    t = literal(t, '    (void)opt_strings_flags(p_tcl, p_tcl_values, &tcl_flags, TRUE);\n', '',
                "didset_string_options reading 'tabclose'")

    # Only cmod_tab can be counted here.  goto_tabpage() is still called from
    # ex_tabnext() and ex_tabonly(), whose rows retire.py pointed away, so the
    # sweep takes those callers; whim36.sh counts what is left after it.
    # may_open_tabpage() still names it, and has no caller now: the sweep takes it.
    gone = cutil.find_definition(t, 'may_open_tabpage')
    n = len([m for m in re.finditer(r'\bcmod_tab\b', t)
             if not (gone and gone[0] <= m.start() < gone[1])])
    if n != 1:
        sys.exit('notabs: cmod_tab outside its declaration -- %d mentions, expected 1' % n)

    path.write_text(t, errors='surrogateescape')
    print('  notabs       nothing makes or reaches a second tab page')


if __name__ == '__main__':
    main()
