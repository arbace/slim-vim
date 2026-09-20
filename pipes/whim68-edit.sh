#!/bin/sh
# Whim phase 68 -- one window, structurally.  See WHIM-GOAL.md.
#
# Usage: pipes/whim68-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# THE INVARIANT THIS ESTABLISHES, and then spends:
#
#   A window is created in exactly two places -- win_alloc_firstwin(), once at
#   startup, and win_split_ins(), whose ONLY caller is aucmd_prepbuf().  win_split(),
#   make_windows() and win_new_tabpage() have no mentions at all.  A tabpage is
#   created once, by alloc_tabpage() in win_alloc_first().  So remove the
#   autocommand window and nothing can add a window or a tabpage ever again:
#
#       firstwin == lastwin  and  first_tabpage->tp_next == NULL
#
#   one_window(), last_window() and only_one_window() are then constant TRUE, and
#   every caller folds.  That is not a guess about the harness -- it is what the
#   two creation sites allow.
#
# WHY THE AUTOCOMMAND WINDOW CAN GO.  aucmd_prepbuf() splits one open only when no
# window shows the buffer, in order to run autocommands there -- and
# apply_autocmds_group() has been `return FALSE` since the phase that removed
# autocommands.  The window would be built to run nothing.
#
# WHAT WAS ALREADY A NO-OP, which is why this removes capability from the source
# and none from the editor:
#
#   win_close() tests last_window() first and answers "cannot close last window",
#       so the calls in ex_quit(), ex_exit() and do_exedit() could never close
#       anything.  ex_quit() and ex_exit() reach getout(0) before them anyway.
#   do_exedit()'s call is guarded by old_curwin != NULL, and its one caller passes
#       NULL.
#   close_windows() loops `wp != NULL && !(firstwin == lastwin)`, false at once,
#       and then over tabpages other than curtab, of which there are none.
#
# WHAT STAYS, because it is not about having two windows: win_comp_pos() and
# last_status() are reached from shell_new_rows() and did_set_laststatus(), so a
# terminal resize and :set laststatus still compute the one window's geometry.
# The frame code does not vanish wholesale, and the probes check that.
#
# THE DELTA: none.  No key, command or option changes.
set -eu

work=${1:?usage: whim68-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 - "$f" <<'PY'
TAG = 'onewindow'
import re, sys
sys.path.insert(0, 'tools')
# tools/cutil.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
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

def count(s, pattern, n, what):
    k = len(re.findall(pattern, s, re.M))
    if k != n:
        die('%s -- matched %d times, expected %d' % (what, k, n))

def _last(s, pattern, f):
    m = list(re.finditer(pattern, s, re.M))[-1]
    start = s.rfind('\n', 0, m.start()) + 1
    return s[:start] + f(s[start:], pattern, 1, re.M)

def repeat(s, pattern, what, n, f):
    count(s, pattern, n, what)
    for _ in range(n):
        try:
            s = _last(s, pattern, f)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    say(what if n == 1 else '%s (%d)' % (what, n))
    return s

def drop_if(s, pattern, what, n=1):
    return repeat(s, pattern, what, n, lambda x, p, c, fl: cutil.drop_if(x, p, c, fl))

def fold_never(s, pattern, what, n=1):
    return repeat(s, pattern, what, n, cutil.fold_never)

def fold_always(s, pattern, what, n=1):
    return repeat(s, pattern, what, n, cutil.fold_always)

def sub(s, pattern, new, what, n=1):
    s, k = re.subn(pattern, new, s, flags=re.M)
    if k != n:
        die('%s -- matched %d times, expected %d' % (what, k, n))
    say(what)
    return s

def literal(s, old, new, what, n=1):
    k = s.count(old)
    if k != n:
        die('%s -- occurs %d times, expected %d' % (what, k, n))
    say(what)
    return s.replace(old, new)

def lines(s, pattern, what, n=1):
    return sub(s, r'^[ \t]*' + pattern + r'\n', '', what, n)

def drop_def(text, name, what):
    text, gone = cutil.delete_definition(text, name)
    if not gone:
        die('%s is not defined' % name)
    say(what)
    return text

# ---- 1. the autocommand window, the last thing that could add a window ----------
def prepbuf(s):
    # TWO narrow splices, not one wide one.  A single cut from the aucmd_win[] search
    # through `curbuf = buf;` also swallows aco->save_curwin_id and
    # aco->save_prevwin_id -- which aucmd_restbuf's surviving else branch reads back
    # through win_find_by_id() -- and it would have compiled, restoring from
    # uninitialised stack.
    a = s.index('    win_T *auc_win = NULL;\n')
    b = s.index('    aco->save_curwin_id = curwin->w_id;\n')
    if not 0 <= a < b:
        die('aucmd_prepbuf -- the aucmd_win search was not found before the saved ids')
    s = s[:a] + '    if (win == NULL)\n    {\n        return;\n    }\n\n' + s[b:]
    say('aucmd_prepbuf building a window to run autocommands in')
    # and the branch that chose between that window and the real one
    c = s.index('    if (win != NULL)\n')
    d = s.index('    curbuf = buf;\n')
    if not c < d:
        die('aucmd_prepbuf -- the window choice was not found before curbuf = buf')
    s = s[:c] + '    curwin = win;\n\n' + s[d:]
    say('aucmd_prepbuf choosing between that window and the real one')
    return s
t = in_function(t, 'aucmd_prepbuf', prepbuf)

def restbuf(s):
    # fold_never, not drop_if: this `if` HAS an else -- the same-window restore --
    # and drop_if refuses that shape on purpose, since deleting the if alone would
    # orphan the else.  fold_never keeps the else body, which is what is left when
    # the index can never be >= 0.
    s = fold_never(s, r'^[ \t]*if \(aco->use_aucmd_win_idx >= 0\)$', 'aucmd_restbuf taking that window down again')
    return s
t = in_function(t, 'aucmd_restbuf', restbuf)
# Both writes to use_aucmd_win_idx went with the branch above, and its only reader
# went with aucmd_restbuf's folded test, so the field itself follows.
t = sub(t, r'^[ \t]*int[ \t]+use_aucmd_win_idx;\n', '', "aco_save_T's window index")

t = drop_def(t, 'win_alloc_popup_win', 'win_alloc_popup_win, which only the autocommand window used')
t = drop_def(t, 'win_init_popup_win', 'win_init_popup_win, the same')
t = sub(t, r'^static aucmdwin_T aucmd_win\[AUCMD_WIN_COUNT\];\n', '', 'the aucmd_win[] table')

# Three places MANAGE that table without ever reading it -- the can_cindent shape
# again.  Each is guarded by auc_win != NULL, which nothing can make true now.
t = lines(t, r'autocmd_init\(\);', 'the call that zeroed the table at startup')
t = drop_def(t, 'autocmd_init', 'autocmd_init, whose body was that memset')
t = sub(t, r'^[ \t]*for \(int i = 0; i < AUCMD_WIN_COUNT; \+\+i\)\n[ \t]*\{\n'
           r'[ \t]*if \(aucmd_win\[i\]\.auc_win != NULL\)\n[ \t]*\{\n'
           r'[ \t]*win_free_lsize\(aucmd_win\[i\]\.auc_win\);\n[ \t]*\}\n[ \t]*\}\n\n?', '',
        'screenalloc freeing the line sizes of windows that do not exist')
t = sub(t, r'^[ \t]*for \(int i = 0; i < AUCMD_WIN_COUNT; \+\+i\)\n[ \t]*\{\n'
           r'[ \t]*if \(aucmd_win\[i\]\.auc_win != NULL && aucmd_win\[i\]\.auc_win->w_lines == NULL && win_alloc_lines\(aucmd_win\[i\]\.auc_win\) == FAIL\)\n'
           r'[ \t]*\{\n[ \t]*outofmem = TRUE;\n[ \t]*break;\n[ \t]*\}\n[ \t]*\}\n\n?', '',
        'screenalloc allocating lines for them')

# ---- 2. the invariant: one window, one tabpage ----------------------------------
# The WHOLE body is replaced, not a `return TRUE;` inserted at the top: leaving the
# old body behind leaves unreachable code that no warning names -- the sweep would
# strip its locals as unused and keep the loop that walked the window list.
def body_true(text, name, what):
    def edit(s):
        head = s[:s.index('{\n') + 2]
        say(what)
        return head + '    return TRUE;\n}\n'
    return in_function(text, name, edit)

t = body_true(t, 'one_window', 'one_window() is constant TRUE')
t = body_true(t, 'last_window', 'last_window() is constant TRUE')
t = body_true(t, 'only_one_window', 'only_one_window() is constant TRUE')

# ---- 3. what those tests guarded ------------------------------------------------
t = in_function(t, 'ex_quit', lambda s: sub(
    s, r'^[ \t]*if \(eap->addr_count > 0\)\n[ \t]*\{\n(?:[^\n]*\n)*?[ \t]*\}\n[ \t]*else\n[ \t]*\{\n[ \t]*wp = curwin;\n[ \t]*\}\n',
    '    wp = curwin;\n', ':quit with a window count, of which there is one'))
t = in_function(t, 'ex_quit', lambda s: fold_always(
    s, r'^[ \t]*if \(only_one_window\(\) && \( \(firstwin == lastwin\)  \|\| eap->addr_count == 0\)\)$', ':quit leaving the editor'))
t = in_function(t, 'ex_quit', lambda s: lines(s, r'win_close\(wp, TRUE\);', ':quit closing a window it can never reach'))
t = in_function(t, 'ex_exit', lambda s: fold_always(
    s, r'^[ \t]*if \(only_one_window\(\)\)$', ':xit leaving the editor'))
t = in_function(t, 'ex_exit', lambda s: lines(s, r'win_close\(curwin, TRUE\);', ':xit closing a window it can never reach'))
t = in_function(t, 'do_exedit', lambda s: drop_if(
    s, r'^[ \t]*if \(old_curwin != NULL\)$', ':edit closing the window it came from, which is never given one'))
t = in_function(t, 'set_curbuf', lambda s: drop_if(
    s, r'^[ \t]*if \(unload\)$', 'unloading a buffer closing the windows that show it'))

# only_one_window() is TRUE, so these terms go rather than the tests.
t = in_function(t, 'check_more', lambda s: literal(s, 'only_one_window() && ', '', 'check_more asking how many windows there are'))
t = in_function(t, 'before_quit_autocmds', lambda s: literal(
    s, ' && only_one_window()', '', 'the quit autocommands asking how many windows there are'))
t = in_function(t, 'create_windows', lambda s: literal(
    s, 'got_int || only_one_window()', 'TRUE', 'the swap-file quit asking how many windows there are'))
t = in_function(t, 'close_buffer', lambda s: literal(
    s, 'abort_if_last && one_window()', 'abort_if_last', 'closing a buffer asking whether its window is the last', 2))

open(path, 'w', errors='surrogateescape').write(t)
PY

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim68-check.sh.
