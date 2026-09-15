#!/usr/bin/env python3
"""The sizing options go, and their values stay: one window has nothing to size against.

Usage:
    python3 tools/nowinsizes.py <file>

After Phase 39 there is one user window, but not one window in the frame tree:
aucmd_prepbuf() still slots its hidden autocommand window in beside it with
win_split_ins() and takes it out again with win_close(), so the arithmetic that
splits, equalises and removes frames still runs, and it reads 'winheight',
'winminheight', 'winwidth', 'winminwidth', 'splitbelow', 'splitright',
'splitkeep', 'equalalways' and 'eadirection' as it goes.

So the ROWS go, and each global KEEPS ITS DEFAULT as an initialiser of its own.
A row is what writes a default into its global at startup (see
tools/orphanopts.py); without one a long reads 0 and a pointer is NULL, and
'winminheight' at 0 or `*p_spk` on NULL is a different editor or a crash.  With
the initialiser the value is exactly what it was under the default settings, and
nothing can change it.  The arithmetic keeps its own temporary writes -- it sets
'winheight' to a size and back -- which a variable allows as well as an option.

'winfixheight' and 'winfixwidth' fix one window's size against another's.  Their
fields are never set now, so every test of them folds, and command_height()'s
loop over fixed-height frames never runs.  'helpheight' has no reader but its own
callback, which the 'winheight' row shared; the sweep takes both.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

DEFAULTS = (
    ('int', 'p_sb', 'FALSE'),
    ('int', 'p_spr', 'FALSE'),
    ('char_u *', 'p_spk', '(char_u *)"cursor"'),
    ('int', 'p_ea', 'TRUE'),
    ('char_u *', 'p_ead', '(char_u *)"both"'),
    ('long', 'p_wh', '1L'),
    ('long', 'p_wmh', '1L'),
    ('long', 'p_wiw', '20L'),
    ('long', 'p_wmw', '1L'),
)


def literal(seg, old, new, what, count=1):
    n = seg.count(old)
    if n != count:
        sys.exit('nowinsizes: %s -- occurs %d times, expected %d' % (what, n, count))
    print('  nowinsizes   %s' % what)
    return seg.replace(old, new)


def subn(seg, pattern, new, what, count=1):
    seg, n = re.subn(pattern, new, seg, flags=re.M)
    if n != count:
        sys.exit('nowinsizes: %s -- matched %d times, expected %d' % (what, n, count))
    print('  nowinsizes   %s' % what)
    return seg


def fold(seg, pattern, what, count=1):
    try:
        seg = cutil.fold_never(seg, pattern, count, re.M)
    except ValueError as e:
        sys.exit('nowinsizes: %s -- %s' % (what, e))
    print('  nowinsizes   %s' % what)
    return seg


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        sys.exit('nowinsizes: %s is not defined at file scope' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    t = path.read_text(errors='surrogateescape')

    # --- the values the rows used to write ---------------------------------------
    for typ, name, value in DEFAULTS:
        t = subn(t, r'^(static\s+%s\s*%s);$' % (re.escape(typ).replace(r'\ ', r'\s*'), name),
                 r'\1 = %s;' % value.replace('\\', r'\\'), '%s keeps its default, %s' % (name, value))

    # --- 'winfixheight' and 'winfixwidth' -----------------------------------------
    W = r'-> w_onebuf_opt\.wo_wf%s '
    def split_ins(s):
        s = fold(s, r'^[ \t]*if \(oldwin' + W % 'w' + r'\)$', 'win_split_ins keeping a fixed width')
        s = fold(s, r'^[ \t]*if \(oldwin' + W % 'h' + r'\)$', 'win_split_ins keeping a fixed height')
        return s
    t = in_function(t, 'win_split_ins', split_ins)
    def remove(s):
        s = fold(s, r'^[ \t]*if \(frp2->fr_win != NULL && frp2->fr_win' + W % 'h' + r'\)$',
                 'winframe_remove passing over a fixed height')
        s = fold(s, r'^[ \t]*if \(frp2->fr_win != NULL && frp2->fr_win' + W % 'w' + r'\)$',
                 'winframe_remove passing over a fixed width')
        return s
    t = in_function(t, 'winframe_remove', remove)
    for name, h in (('frame_fixed_height', 'h'), ('frame_fixed_width', 'w')):
        t = in_function(t, name, lambda s, h=h, name=name: literal(
            s, 'return frp->fr_win-> w_onebuf_opt.wo_wf%s ;' % h, 'return FALSE;', '%s of a window' % name))
    for name, h, dim in (('frame_setheight', 'h', 'height'), ('frame_setwidth', 'w', 'width')):
        def setdim(s, h=h, dim=dim):
            s = fold(s, r'^[ \t]*if \(frp != curfrp && frp->fr_win != NULL && frp->fr_win' + W % h + r'\)$',
                     'frame_set%s reserving a fixed %s' % (dim, dim))
            s = fold(s, r'^[ \t]*if \(room_reserved > 0 && frp->fr_win != NULL && frp->fr_win' + W % h + r'\)$',
                     'frame_set%s sparing a fixed %s' % (dim, dim))
            return s
        t = in_function(t, name, setdim)
    t = in_function(t, 'command_height', lambda s: subn(
        s, r'^[ \t]*while \(frp->fr_prev != NULL && frp->fr_layout == FR_LEAF && frp->fr_win' + W % 'h' +
           r'\)\n[ \t]*\{\n[ \t]*frp = frp->fr_prev;\n[ \t]*\}\n\n', '',
        'command_height stepping over fixed heights'))
    def enter(s):
        s = literal(s, ' && !curwin-> w_onebuf_opt.wo_wfh ', '', 'win_enter_ext sparing a fixed height')
        s = literal(s, ' && !curwin-> w_onebuf_opt.wo_wfw ', '', 'win_enter_ext sparing a fixed width')
        return s
    t = in_function(t, 'win_enter_ext', enter)
    def close(s):
        try:
            s = cutil.drop_if(s, r'^[ \t]*if \(bt_quickfix\(buf\) && win_valid && win->w_buffer == buf\)$', flags=re.M)
        except ValueError as e:
            sys.exit('nowinsizes: close_buffer clearing a quickfix height -- %s' % e)
        print('  nowinsizes   close_buffer clearing a quickfix height')
        return s
    t = in_function(t, 'close_buffer', close)
    for wv, fld in (('WFH', 'wfh'), ('WFW', 'wfw')):
        t = subn(t, r'^[ \t]*case   \(idopt_T\)\(PV_WIN \+ \(int\)\(WV_%s\)\)  :\n'
                    r'[ \t]*return \(char_u \*\)&\(curwin-> w_onebuf_opt\.wo_%s \);\n' % (wv, fld), '',
                 'get_varp for WV_%s' % wv)

    n = len(re.findall(r'\bwo_wf[hw]\b', t))
    if n != 2:
        sys.exit('nowinsizes: wo_wfh and wo_wfw outside their declarations -- %d mentions, expected 2' % n)

    path.write_text(t, errors='surrogateescape')
    print('  nowinsizes   the sizes are fixed at their defaults, and no window is fixed against another')


if __name__ == '__main__':
    main()
