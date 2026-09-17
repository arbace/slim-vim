#!/bin/sh
# Whim phase 72 -- one window, one tabpage, structurally.  See WHIM-GOAL.md.
#
# Usage: pipes/whim72-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# THE INVARIANT IS PROVABLE, not imposed -- the phase 68 shape rather than the
# phase 70 one.  Windows are created in exactly one place: win_alloc(NULL, FALSE)
# from win_alloc_firstwin(), whose only caller is win_alloc_first() at startup.
# alloc_tabpage() is called exactly once, from the same function, and curtab is set
# to it there.  :tabnew, :tabedit, :split, :new and the rest are already ex_ni, and
# aucmd_win went in phase 68.  So firstwin == lastwin == curwin and
# first_tabpage == curtab, always, and this phase deletes the traversal that
# pretended otherwise.
#
# TWO LAYERS, FOLDED AS A PAIR.  Nearly every tabpage walk immediately contains
#
#     for ((wp) = ((tp) == curtab) ? firstwin : (tp)->tp_firstwin; (wp); ...)
#
# so folding the outer walk to `tp = curtab` makes that ternary constant-fold to
# firstwin, and folding the inner one then gives curwin.  Cutting one layer without
# the other would leave half a traversal at every one of these sites.
#
# SEVEN BODIES ARE REWRITTEN, NOT FOLDED, and they were found BEFORE writing a line
# of this file rather than after three dry runs.  Folding a walk deletes its `for`
# header, and C binds break/continue to the nearest enclosing loop or switch -- brace
# depth has nothing to do with it.  In phase 71 getout() failed to compile that way,
# which is the cheap outcome, and buflist_findpat() COMPILED FINE AND CHANGED
# BEHAVIOUR.  So fold_walks() below audits every body it is about to fold and
# REFUSES if any break/continue would rebind:
#
#   aucmd_prepbuf        break   -- the walk searched for the window showing a buffer
#   can_unload_buffer    break   -- same search, for "is it on screen"
#   borrow_stl_vsep_hl   both    -- two walks; the whole function collapses
#   current_win_nr       break   -- counts to the window, so: 1
#   current_tab_nr       break   -- counts to the tabpage, so: 1
#   getout               both    -- a tabpage walk that re-seeds next_tp and breaks
#   create_windows       break   -- a rewind loop over w_next, twice
#
# THE TABPAGE-SWITCHING GROUP IS DEAD BEHIND ONE GATE.  goto_tabpage_tp()'s whole
# body is `if (tp != curtab && leave_tabpage(...) == OK)`, which with one tabpage is
# never true.  Folding that gate away orphans leave_tabpage, enter_tabpage,
# valid_tabpage and use_tabpage, and the sweep then removes them -- taking the last
# readers of tp_firstwin, tp_lastwin and tp_prevwin with them.  Nothing here deletes
# those functions by name; removing the one gate is what kills them.
#
# WHAT STAYS, deliberately:
#   * the FRAME layer -- topframe, frame_T, fr_next, fr_child, fr_parent.  One window
#     still has one frame, and new_frame()/topframe are load-bearing for sizing.
#     Cutting frames is its own phase.
#   * b_nwindows.  Tracing every write: = 1 at window creation, balanced ++/-- pairs
#     in enter_buffer and aucmd_restbuf, and -- in close_buffer when the window drops
#     the buffer.  It is genuinely 0 after that, so `<= 0` and `== 0` are live
#     "no longer displayed" tests.  An earlier plan folded all 20 sites to a constant
#     1; that would have broken buffer release silently.
#   * prevwin and w_id.  aucmd_prepbuf/aucmd_restbuf save and restore the window by
#     id, and the incsearch state compares curwin->w_id, so neither is list state.
#   * the `curwin == NULL` guards that were `firstwin == NULL` in shell_new_rows,
#     shell_new_columns, min_rows and min_rows_for_all_tabpages.  They exist because
#     a resize can arrive before win_alloc_first(), and proving that it cannot is not
#     this phase's job.
#
# THE DELTA: none expected.  Every window and tabpage Ex command is already ex_ni, so
# no exsweep row can move; declared empty and left for whimdelta.sh to correct.
set -eu

work=${1:?usage: whim72-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 - "$f" <<'PY'
TAG = 'onewin'
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

def fold_never(text, fn, pattern, what, n=1):
    def edit(s):
        try:
            return cutil.fold_never(s, pattern, n, re.M)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    out = in_function(text, fn, edit)
    say(what)
    return out

def binds_out(raw):
    """True if `raw` holds a break/continue that binds to the loop AROUND it.

    Not a depth test.  C binds break to the nearest enclosing loop or switch, so the
    question is whether one of those lies between the statement and the body's edge.
    An earlier version of this tested brace depth and would have passed getout().
    """
    rb = cutil.blank(raw)
    spans = []
    for m in re.finditer(r'\b(for|while|switch|do)\b', rb):
        j = rb.find('{', m.end())
        if j >= 0:
            k = cutil.match(raw, j, rb)
            if k > 0:
                spans.append((j, k))
    for kw in ('break', 'continue'):
        for m in re.finditer(r'\b%s\b[ \t]*;' % kw, rb):
            if not any(a < m.start() < z for a, z in spans):
                return True
    return False

def fold_walks(text, head_re, subst, what):
    """Fold every walk of one shape, refusing if any body's break/continue rebinds.

    Walks of a single shape are disjoint, so the matches are rewritten back to front
    and the blanked copy stays valid for every offset still to be processed.
    """
    pat = re.compile(r'^(?P<ind>[ \t]*)' + head_re + r'[ \t]*\n[ \t]*\{\n', re.M)
    b = cutil.blank(text)
    ms = list(pat.finditer(text))
    if not ms:
        die('%s -- no walk of this shape is left to fold' % what)
    unsafe = []
    for m in reversed(ms):
        o = text.index('{', m.start())
        c = cutil.match(text, o, b)
        if c < 0:
            die('%s -- unbalanced block' % what)
        raw = text[text.index('\n', o) + 1:text.rfind('\n', 0, c) + 1]
        if binds_out(raw):
            unsafe.append(text[:m.start()].count('\n') + 1)
            continue
        body = cutil._dedent4(raw)
        end = text.index('\n', c) + 1
        text = text[:m.start()] + m.group('ind') + subst(m) + '\n' + body + text[end:]
    if unsafe:
        die('%s -- %d walk(s) still carry an escaping break/continue and need an '
            'explicit rewrite: lines %s'
            % (what, len(unsafe), ' '.join(str(n) for n in sorted(unsafe))))
    say('%s (%d)' % (what, len(ms)))
    return text

def drop_walk(text, fn, head_re, repl, what, n=1):
    """Replace `for (<head>)` and its block with `repl`, inside one function."""
    def edit(s):
        pat = re.compile(r'^[ \t]*' + head_re + r'[ \t]*\n[ \t]*\{\n', re.M)
        k = len(pat.findall(s))
        if k != n:
            die('%s -- the walk matches %d times, expected %d' % (what, k, n))
        out = s
        for _ in range(n):
            m = pat.search(out)
            b = cutil.blank(out)
            o = out.index('{', m.start())
            c = cutil.match(out, o, b)
            end = out.index('\n', c) + 1
            out = out[:m.start()] + repl + out[end:]
        return out
    out = in_function(text, fn, edit)
    say(what)
    return out

def replace_block(text, fn, anchor_re, repl, what):
    """Replace a brace-matched block, anchored on the line that opens it."""
    def edit(s):
        m = re.search(anchor_re, s, re.M)
        if not m:
            die('%s -- no line matches %r' % (what, anchor_re))
        k = s.rfind('\n', 0, m.start()) + 1
        b = cutil.blank(s)
        o = s.index('{', m.start())
        c = cutil.match(s, o, b)
        if c < 0:
            die('%s -- unbalanced block' % what)
        return s[:k] + repl + s[s.index('\n', c) + 1:]
    out = in_function(text, fn, edit)
    say(what)
    return out

# ---- 1. the constant tests, before anything renames what they compare -----------
# ONE_WINDOW, expanded at three sites and missed by phase 68, which only folded the
# one_window()/last_window()/only_one_window() functions.
t = literal(t, '(firstwin == lastwin) ', 'TRUE ', 'ONE_WINDOW, expanded in place', 3)
t = literal(t, 'wp == firstwin', 'TRUE', 'win_update asking whether this is the top window', 2)
t = literal(t, 'wp == lastwin', 'wp == curwin', 'win_redr_ruler asking for the bottom window')

# ---- 2. the seven bodies whose break/continue binds to the walk -----------------
t = drop_walk(t, 'aucmd_prepbuf',
              r'for \(\(win\) = firstwin; \(win\) != NULL; \(win\) = \(win\)->w_next\)',
              '        win = (curwin->w_buffer == buf) ? curwin : NULL;\n',
              'aucmd_prepbuf searching for the window showing a buffer')
t = drop_walk(t, 'can_unload_buffer',
              r'for \(\(wp\) = firstwin; \(wp\) != NULL; \(wp\) = \(wp\)->w_next\)',
              '''        if (curwin->w_buffer == buf)
        {
            can_unload = FALSE;
        }
''', 'can_unload_buffer asking whether the buffer is on screen')

# borrow_stl_vsep_hl lends a status line's highlight to the vertical separator
# beside it.  With one window there is no beside: the inner walk's only candidate is
# `left` itself, which it skips, so `neighbour` stays NULL and every iteration
# continues.  The function cannot do anything, and its two calls go with it.
t = lines(t, r'borrow_stl_vsep_hl\(\);', 'the two calls to the separator-highlight pass', 2)
out, ok = cutil.delete_definition(t, 'borrow_stl_vsep_hl')
if not ok:
    die('borrow_stl_vsep_hl is not defined')
t = out
say('borrow_stl_vsep_hl, which had no window to borrow from')

t = replace_body(t, 'current_win_nr', '    return 1;\n', 'current_win_nr, which counted to the window')
t = replace_body(t, 'current_tab_nr', '    return 1;\n', 'current_tab_nr, which counted to the tabpage')

t = replace_block(t, 'getout', r'^[ \t]*for \(tp = first_tabpage; tp != NULL; tp = next_tp\)$',
'''        if (curwin->w_buffer != NULL && buf_valid(curwin->w_buffer))
        {
            buf = curwin->w_buffer;
            if ( ((buf)->b_ct_di.di_tv.vval.v_number)  != -1)
            {
                bufref_T bufref;

                set_bufref(&bufref, buf);
                apply_autocmds(EVENT_BUFWINLEAVE, buf->b_fname, buf->b_fname, FALSE, buf);
                if (bufref_valid(&bufref))
                {
                     ((buf)->b_ct_di.di_tv.vval.v_number)  = -1;
                }
            }
        }
''', 'quitting walking every window of every tabpage')

# create_windows rewinds to firstwin and walks w_next up to a thousand times, so that
# opening one buffer can restart the scan.  With one window the scan is one window.
t = replace_body(t, 'create_windows', '''    ++autocmd_no_enter;
    ++autocmd_no_leave;

    curbuf = curwin->w_buffer;
    if (curbuf->b_ml.ml_mfp == NULL)
    {
        (void)open_buffer(FALSE, NULL, 0);
    }
    ui_breakcheck();
    if (got_int)
    {
        (void)vgetc();
    }

    curbuf = curwin->w_buffer;
    --autocmd_no_enter;
    --autocmd_no_leave;
''', 'the startup scan rewinding over the window list')

# ---- 3. the validity questions all become identity ------------------------------
t = replace_body(t, 'win_valid', '    return win != NULL && win == curwin;\n',
                 'win_valid, which walked the list for the window it was given')
t = replace_body(t, 'win_valid_any_tab', '    return win != NULL && win == curwin;\n',
                 'win_valid_any_tab, which walked every tabpage for it')
t = replace_body(t, 'win_find_by_id', '    return (curwin->w_id == id) ? curwin : NULL;\n',
                 'win_find_by_id, which walked the list by id')
t = replace_body(t, 'valid_tabpage', '    return tpc == curtab;\n',
                 'valid_tabpage, which walked the tabpage list')

# ---- 4. the one gate the whole tabpage-switching group hangs from ---------------
t = fold_never(t, 'goto_tabpage_tp', r'^[ \t]*if \(tp != curtab && leave_tabpage\(',
               'switching to another tabpage')

# and the two guards that reached goto_tabpage_win with a window that is not curwin
t = fold_never(t, 'close_buffer', r'^[ \t]*if \(is_curwin && curwin != win && win_valid\)$',
               'closing a buffer from another window')
t = fold_never(t, 'buf_freeall', r'^[ \t]*if \(is_curwin && curwin != the_curwin && win_valid_any_tab\(the_curwin\)\)$',
               'freeing a buffer from another window')

# ---- 5. allocation: one window, one tabpage, linked to nothing ------------------
# win_init() copies one window's state into another and is reachable only through
# win_alloc_firstwin()'s oldwin != NULL arm -- and the one caller passes NULL.
t = replace_body(t, 'win_alloc_firstwin', '''    curwin = win_alloc(NULL, FALSE);
    if (curwin == NULL)
    {
        return FAIL;
    }
    curbuf = buflist_new(NULL, NULL, 1L, BLN_LISTED);
    if (curbuf == NULL)
    {
        return FAIL;
    }
    curwin->w_buffer = curbuf;
    curbuf->b_nwindows = 1;
    curwin_init();

    new_frame(curwin);
    if (curwin->w_frame == NULL)
    {
        return FAIL;
    }
    topframe = curwin->w_frame;
    topframe->fr_width =  Columns ;
    topframe->fr_height = Rows - p_ch;

    return OK;
''', 'win_alloc_firstwin cloning an existing window')

t = replace_body(t, 'win_alloc_first', '''    if (win_alloc_firstwin(NULL) == FAIL)
    {
        return FAIL;
    }

    curtab = alloc_tabpage();
    if (curtab == NULL)
    {
        return FAIL;
    }
    unuse_tabpage(curtab);

    return OK;
''', 'the first tabpage being the head of a list')

t = fold_never(t, 'win_alloc', r'^[ \t]*if \(!hidden\)$', 'win_alloc appending to the window list')

t = replace_body(t, 'unuse_tabpage', '''    tp->tp_topframe = topframe;
    tp->tp_curwin = curwin;
''', 'a tabpage remembering the ends of its window list')

t = replace_body(t, 'win_rest_invalid', '''    redraw_win_later(wp, UPD_NOT_VALID);
    wp->w_redr_status = true;
    redraw_cmdline = TRUE;
''', 'win_rest_invalid invalidating every window after one')

# ---- 6. every remaining walk, inner layer first ---------------------------------
NESTED = (r'for \(\((?P<v>\w+)\) = \(\((?P<tv>\w+)\) == (?:NULL \|\| \((?P=tv)\) == )?curtab\)'
          r' *\? firstwin : \((?P=tv)\)->tp_firstwin; \((?P=v)\); \((?P=v)\) = \((?P=v)\)->w_next\)')
TABS   = (r'for \(\((?P<v>\w+)\) = first_tabpage; \((?P=v)\) != NULL;'
          r' \((?P=v)\) = \((?P=v)\)->tp_next\)')
WINS   = (r'for \(\((?P<v>\w+)\) = firstwin; \((?P=v)\) != NULL;'
          r' \((?P=v)\) = \((?P=v)\)->w_next\)')

t = fold_walks(t, NESTED, lambda m: '%s = curwin;' % m.group('v'),
               'the window walk inside every tabpage walk')
t = fold_walks(t, TABS, lambda m: '%s = curtab;' % m.group('v'),
               'every walk over the tabpage list')
t = fold_walks(t, WINS, lambda m: '%s = curwin;' % m.group('v'),
               'every walk over the window list')

# ---- 6b. the window list read WITHOUT walking it ---------------------------------
# win_ins_lines, win_del_lines and win_do_lines ask `wp->w_next` as a LAYOUT question
# -- "is there anything below this window on the screen" -- rather than to traverse.
# No `for` head mentions them, so the walk audit could not see them, and w_next
# survived the fold with six readers.  With one window the answer is always NULL.
#
# The two win_rest_invalid(wp->w_next) calls are not cosmetic: win_rest_invalid no
# longer walks, so it dereferences its argument unconditionally, and passing NULL
# would crash.  Folding them away is required.
t = in_function(t, 'win_ins_lines', lambda s: literal(
    s, '    if (wp->w_next != NULL || wp->w_status_height)\n',
    '    if (wp->w_status_height)\n', 'scrolling asking whether a window is below'))
t = in_function(t, 'win_ins_lines', lambda s: literal(s, '''        else if (wp->w_next)
        {
            return FAIL;
        }
''', '', 'scrolling refusing when a window is below'))
t = in_function(t, 'win_ins_lines', lambda s: literal(s, '''        if (did_delete)
        {
            wp->w_redr_status = true;
            win_rest_invalid( ((wp)->w_next) );
        }
''', '''        if (did_delete)
        {
            wp->w_redr_status = true;
        }
''', 'scrolling invalidating the window below'))

t = in_function(t, 'win_del_lines', lambda s: literal(
    s, '    if (wp->w_next || wp->w_status_height || cmdline_row < Rows - 1)\n',
    '    if (wp->w_status_height || cmdline_row < Rows - 1)\n',
    'deleting lines asking whether a window is below'))
t = in_function(t, 'win_del_lines', lambda s: literal(s, '''            wp->w_redr_status = true;
            win_rest_invalid(wp->w_next);
''', '''            wp->w_redr_status = true;
''', 'deleting lines invalidating the window below'))

t = in_function(t, 'win_do_lines', lambda s: literal(s, '''    if (wp->w_next != NULL && p_tf)
    {
        return FAIL;
    }

''', '', "'termfastscroll' refusing to scroll a window that has one below"))

t = lines(t, r'win_T[ \t]+\*w_next;', 'the window list pointer in win_T')

# ---- 6c. what the folds left set but never read ----------------------------------
# Folding `for ((tp) = first_tabpage; ...)` into `tp = curtab;` leaves a variable
# nothing goes on to read, and gcc calls that -Wunused-but-set-variable, which
# deadsweep.py does not handle -- it knows unused-variable and unused-function and
# nothing else.  Five of the fourteen assignments are unread; the other nine are.
# EIGHT functions, not the five gcc listed -- that list was truncated at the first
# twenty warnings.  check_changed_any and min_rows_for_all_tabpages are NOT here:
# they still read their tp, so the assignment stays.  The count per function is
# stated because a fold that is not counted is a guess, and changed_common has three.
for fn, var, n in (('setfname', 'tab', 1), ('changed_common', 'tp', 3),
                   ('mark_adjust_internal', 'tab', 1), ('set_options_default', 'tp', 1),
                   ('did_set_global_listfillchars', 'tp', 1),
                   ('check_chars_options', 'tp', 1), ('check_lnums_both', 'tp', 1),
                   ('screenalloc', 'tp', 2)):
    t = in_function(t, fn, lambda s, v=var, k=n: lines(s, r'%s = curtab;' % v,
                                                      'the tabpage %s no longer walks' % fn, k))
    t = in_function(t, fn, lambda s, v=var: lines(s, r'tabpage_T[ \t]+\*%s;' % v,
                                                 'and the variable that held it'))

# ---- 7. what is left of the two lists -------------------------------------------
t = lines(t, r'static win_T[ \t]+\*firstwin;', 'firstwin')
t = lines(t, r'static win_T[ \t]+\*lastwin;', 'lastwin')
t = lines(t, r'static tabpage_T[ \t]+\*first_tabpage;', 'first_tabpage')

# Every mention that survives is a window that IS curwin -- layout state read through
# the list head (win_init_size writing firstwin->w_height, compute_cmdrow reading
# lastwin->w_winrow), or a function the sweep is about to remove.  Renaming rather
# than deleting is what keeps the layout arithmetic intact.
n = len(re.findall(r'\bfirstwin\b', t)) + len(re.findall(r'\blastwin\b', t))
t = re.sub(r'\bfirstwin\b', 'curwin', t)
t = re.sub(r'\blastwin\b', 'curwin', t)
say('the list heads read as layout state (%d mentions -> curwin)' % n)

open(path, 'w', errors='surrogateescape').write(t)
PY

python3 tools/create_cmdidxs.py "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim72-check.sh.
