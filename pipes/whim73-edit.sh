#!/bin/sh
# Whim phase 73 -- one frame.  See WHIM-GOAL.md.
#
# Usage: pipes/whim73-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# THE STRONGEST INVARIANT OF THIS RUN, and it is proved by absence rather than by
# argument: GREPPING THE WHOLE FILE FOR A WRITE TO fr_child, fr_next, fr_prev OR
# fr_parent RETURNS NOTHING AT ALL.  The frame tree is never linked.
#
#   * alloc_clear(sizeof(frame_T)) appears exactly once, in new_frame(), whose only
#     caller is win_alloc_firstwin() -- itself called once, from win_alloc_first();
#   * new_frame() writes fr_layout = FR_LEAF and fr_win = wp, and nothing else ever
#     writes fr_layout;
#   * win_alloc_firstwin() sets topframe = curwin->w_frame;
#   * there is no frame_insert, frame_append, frame_remove, win_split or
#     win_split_ins anywhere -- they went with the window layout in phase 68/72.
#
# So topframe == curwin->w_frame, fr_layout is FR_LEAF forever, and fr_child,
# fr_next, fr_prev and fr_parent are permanently NULL.  Every FR_ROW and FR_COL
# branch is dead, every fr_child walk iterates zero times, and every fr_parent walk
# terminates on its first test.  This phase is therefore a set of BODY REPLACEMENTS,
# not a fold campaign: each function keeps the arm that runs and loses the arms that
# cannot.
#
# THE BREAK HAZARD IS HANDLED BY CONSTRUCTION.  The audit named four loops whose
# break binds to the loop being removed -- stl_connected, frame_new_height,
# frame_new_width (twice) and command_height -- and all four are in the
# replace-whole-body set, so nothing is folded out from under a break.  That is the
# phase 71 lesson applied ahead of time rather than after three dry runs.
#
# WHAT IS NOT A CONSTANT, and must keep its arithmetic:
#   * frame_minheight() reads p_wh, p_wmh and w_status_height.  min_rows() and
#     did_set_cmdheight()'s clamp depend on the number it returns, so the leaf arm
#     stays exactly as it is; only the recursion goes.  Replacing it with a literal
#     would silently change what :set cmdheight= accepts.
#   * fr_width and fr_height on the one frame are live layout state, read by
#     win_do_lines, screen_ins_lines, screen_del_lines, redraw_block, screen_line,
#     win_line and did_set_cmdheight.  The FIELDS stay; only the tree goes.
#
# WHAT GOES BY CASCADE: frame_fixed_height and frame_fixed_width reach `return FALSE`
# and their callers' `wfh`/`wfw` loops vanish, so the sweep removes them.  The FR_ROW
# and FR_COL enumerators lose every reader.  Nothing here deletes those by name.
#
# THE DELTA: none expected.  Every window-splitting and resizing Ex command is
# already ex_ni, and :set cmdheight= keeps the same accepted range because
# frame_minheight keeps its arithmetic.  Declared empty, left for whimdelta.sh.
set -eu

work=${1:?usage: whim73-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 - "$f" <<'PY'
TAG = 'oneframe'
import re, sys
sys.path.insert(0, 'tools')
import cutil
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()

def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))

def say(what):
    print('  %-12s %s' % (TAG, what))

def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        die('%s is not defined' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]

def literal(s, old, new, what, n=1):
    k = s.count(old)
    if k != n:
        die('%s -- occurs %d times, expected %d' % (what, k, n))
    say(what)
    return s.replace(old, new)

def lines(text, pattern, what, n=1):
    rx = re.compile(r'^[ \t]*' + pattern + r'[ \t]*\n', re.M)
    k = len(rx.findall(text))
    if k != n:
        die('%s -- %d lines match, expected %d' % (what, k, n))
    say(what)
    return rx.sub('', text)

def replace_body(text, name, new_body, what):
    def edit(s):
        return s[:s.index('{\n') + 2] + new_body + '}\n'
    out = in_function(text, name, edit)
    say(what)
    return out

# THE TREE IS NEVER LINKED -- assert it here, in the phase, rather than trusting the
# survey that found it.  If a later upstream ever links a frame again, this fails
# loudly instead of producing an editor that silently mis-sizes its one window.
w = re.findall(r'fr_(?:child|next|prev|parent)[ \t]*(?:=[^=]|\+\+|--)', t)
if w:
    die('the frame tree IS linked somewhere (%d writes) -- the invariant this phase '
        'rests on is false, and every replacement below would be wrong' % len(w))
say('confirmed: nothing writes fr_child, fr_next, fr_prev or fr_parent')

# ---- 1. the two predicates that only ever answered about a subtree --------------
t = replace_body(t, 'frame_fixed_height', '    return FALSE;\n',
                 'frame_fixed_height, asked of a leaf')
t = replace_body(t, 'frame_fixed_width', '    return FALSE;\n',
                 'frame_fixed_width, asked of a leaf')

# ---- 2. the minima keep their ARITHMETIC, and lose only the recursion -----------
t = replace_body(t, 'frame_minheight', '''    int         m;

    if (topfrp->fr_win == next_curwin)
    {
        m = p_wh + topfrp->fr_win->w_status_height;
    }
    else
    {
        m = p_wmh + topfrp->fr_win->w_status_height;
        if (topfrp->fr_win == curwin && next_curwin == NULL)
        {
            if (p_wmh == 0)
            {
                ++m;
            }
            m +=  0 ;
        }
    }

    return m;
''', 'frame_minheight recursing into a row or column')
t = replace_body(t, 'frame_minwidth', '''    int m;

    if (topfrp->fr_win == next_curwin)
    {
        m = p_wiw + topfrp->fr_win->w_vsep_width;
    }
    else
    {
        m = p_wmw + topfrp->fr_win->w_vsep_width;
        if (p_wmw == 0 && topfrp->fr_win == curwin && next_curwin == NULL)
        {
            ++m;
        }
    }

    return m;
''', 'frame_minwidth recursing into a row or column')

# ---- 3. the size checks, which only ever disagreed with a child ------------------
t = replace_body(t, 'frame_check_height', '    return topfrp->fr_height == height;\n',
                 'frame_check_height comparing against children')
t = replace_body(t, 'frame_check_width', '    return topfrp->fr_width == width;\n',
                 'frame_check_width comparing against children')

# ---- 4. position, height and width of the one frame -----------------------------
t = replace_body(t, 'frame_comp_pos', '''    win_T       *wp;
    int         h;

    wp = topfrp->fr_win;
    if (wp != NULL)
    {
        if (wp->w_winrow != *row || wp->w_wincol != *col)
        {
            wp->w_winrow = *row;
            wp->w_wincol = *col;
            redraw_win_later(wp, UPD_NOT_VALID);
            wp->w_redr_status = true;
        }
        h =  (wp)->w_height  + wp->w_status_height;
        *row += h > topfrp->fr_height ? topfrp->fr_height : h;
        *col += wp->w_width + wp->w_vsep_width;
    }
''', 'frame_comp_pos descending into children')

# frame_new_height keeps the cmdheight adjustment -- topfrp IS the root, so
# fr_parent == NULL is always true and `set_ch` decides it, exactly as before.
t = replace_body(t, 'frame_new_height', '''    if (set_ch)
    {
        int new_ch = MAX(min_set_ch, p_ch + topfrp->fr_height - height);
        int save_ch = min_set_ch;
        if (new_ch != p_ch)
        {
            set_option_value((char_u *)"cmdheight", new_ch, NULL, 0);
        }
        min_set_ch = save_ch;
        height = MIN(height,  (Rows - p_ch - tabline_height()) );
    }
    win_new_height(topfrp->fr_win, height - topfrp->fr_win->w_status_height -  0 );
    topfrp->fr_height = height;
''', 'frame_new_height distributing height over children')

# frame_new_width: the leaf arm walked to the root to decide whether a vertical
# separator is needed.  With no parent it is not.
t = replace_body(t, 'frame_new_width', '''    win_T       *wp;

    wp = topfrp->fr_win;
    wp->w_vsep_width = 0;
    win_new_width(wp, width - wp->w_vsep_width);
    topfrp->fr_width = width;
''', 'frame_new_width distributing width over children')

# ---- 5. resizing the one frame ---------------------------------------------------
t = replace_body(t, 'frame_setheight', '''    if (curfrp->fr_height == height)
    {
        return;
    }

    if (height > 0)
    {
        frame_new_height(curfrp, height, FALSE, FALSE, TRUE);
    }
''', 'frame_setheight taking room from siblings')
t = replace_body(t, 'frame_setwidth', '''    if (curfrp->fr_width == width)
    {
        return;
    }
''', 'frame_setwidth taking room from siblings')
t = replace_body(t, 'frame_add_height', '''    frame_new_height(frp, frp->fr_height + n, FALSE, FALSE, FALSE);
''', 'frame_add_height propagating to parents')

# ---- 6. the status line, and the command line's room -----------------------------
# last_status_rec's FR_LEAF arm keeps everything it did; its inner `while` tested
# fp->fr_height <= frame_minheight(fp, NULL) and, on the root, reported
# e_not_enough_room -- which is still reachable and still the right answer.
t = replace_body(t, 'last_status_rec', '''    win_T       *wp;

    wp = fr->fr_win;
    if (wp->w_status_height != 0 && !statusline)
    {
        win_new_height(wp, wp->w_height + wp->w_status_height);
        wp->w_status_height = 0;
        comp_col();
    }
    else if (wp->w_status_height == 0 && statusline)
    {
        if (fr->fr_height <= frame_minheight(fr, NULL))
        {
            emsg(_(e_not_enough_room));
            return;
        }
        wp->w_status_height = statusline_height(wp);
        win_new_height(wp, wp->w_height - wp->w_status_height);
        comp_col();
        redraw_all_later(UPD_SOME_VALID);
    }
    if (abs(wp->w_height - wp->w_prev_height) == 1)
    {
        wp->w_prev_height = wp->w_height;
    }
''', 'last_status_rec descending a row or column of frames')

# command_height walked to the widest ancestor and then took height from previous
# siblings.  There is one frame: it is the root, and it has no fr_prev, so the taking
# loop runs at most once.
t = replace_body(t, 'command_height', '''    int         old_p_ch = curtab->tp_ch_used;
    frame_T     *frp = curwin->w_frame;

    if (p_ch > old_p_ch && command_frame_height)
    {
        int h = MIN(p_ch - old_p_ch, frp->fr_height - frame_minheight(frp, NULL));
        frame_add_height(frp, -h);
        old_p_ch += h;
    }
    if (p_ch < old_p_ch && command_frame_height)
    {
        frame_add_height(frp, (int)(old_p_ch - p_ch));
    }

    win_comp_pos();
    win_fix_scroll(true);
    cmdline_row = Rows - p_ch;
    redraw_cmdline = TRUE;

    if (msg_scrolled == 0 && full_screen)
    {
        screen_fill(cmdline_row, (int)Rows, 0, (int)Columns, ' ', ' ', 0);
        msg_row = cmdline_row;
    }

    curtab->tp_ch_used = p_ch;
    min_set_ch = p_ch;
''', 'command_height walking to the widest ancestor')

# ---- 7. a status line has no neighbour to connect to -----------------------------
t = replace_body(t, 'stl_connected', '    return FALSE;\n',
                 'stl_connected, which climbed the tree for a neighbour')

# ---- 8. what is left of the tree -------------------------------------------------
t = lines(t, r'frame_T[ \t]+\*fr_parent;', 'the parent pointer')
t = lines(t, r'frame_T[ \t]+\*fr_next;', 'the next pointer')
t = lines(t, r'frame_T[ \t]+\*fr_prev;', 'the previous pointer')
t = lines(t, r'frame_T[ \t]+\*fr_child;', 'the child pointer')

open(path, 'w', errors='surrogateescape').write(t)
PY

python3 tools/create_cmdidxs.py "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim73-check.sh.
