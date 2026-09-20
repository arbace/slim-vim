#!/bin/sh
# Whim phase 62 -- no buffer-type, file-type, listing, jump, update-time or autowrite options.  See WHIM-GOAL.md.
#
# Usage: pipes/whim62-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
#   'buflisted'     every reader chose which autocommand event to fire, and
#                   apply_autocmds_group() is `return FALSE` -- or searched a
#                   buffer list of one
#   'filetype'      every reader fed the FileType event, which cannot fire, or
#                   fix_help_buffer(), and :help is ex_ni
#   'buftype'       live only through :set bt=: nofile, nowrite, acwrite and prompt
#                   refused :w and skipped reading; help set b_help.  Nothing
#                   inside the editor ever set it.  bt_dontwrite(),
#                   bt_nofilename(), bt_nofileread() and bt_prompt() fold as false
#                   at every caller
#   'jumpoptions'   empty: the "stack" behaviour of the jump list folds away
#   'updatetime'    dead, though it looked live: after that long idle,
#                   inchar_loop() asked trigger_cursorhold(), which is `return
#                   FALSE`, and called before_blocking(), whose swap sync reaches
#                   an empty ml_sync_all() and whose terminal flush only acts
#                   inside a screen redraw, never at idle.  So the idle wait goes:
#                   a wait with no timeout blocks at once, and before_blocking(),
#                   updatescript() and ml_sync_all() go with the CursorHold probe
#   'autowrite'     off: autowrite() always failed and autowrite_all() returned,
#   'autowriteall'  so their callers and the CCGD_AW flag fold
#
# THE DELTA: none the harnesses record.  The probes check the seven are unknown
# and that :w still writes.
set -eu

work=${1:?usage: whim62-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 - "$f" <<'PY'
TAG = 'nobufopts'
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

def count(s, pattern, n, what):
    k = len(re.findall(pattern, s, re.M))
    if k != n:
        die('%s -- matched %d times, expected %d' % (what, k, n))

def fold_never(s, pattern, what, n=1):
    count(s, pattern, n, what)
    for _ in range(n):
        try:
            s = cutil.fold_never(s, pattern, 1, re.M) if len(re.findall(pattern, s, re.M)) == 1 else _last(s, pattern, cutil.fold_never)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    say(what)
    return s

def _last(s, pattern, f):
    m = list(re.finditer(pattern, s, re.M))[-1]
    start = s.rfind('\n', 0, m.start()) + 1
    return s[:start] + f(s[start:], pattern, 1, re.M)

def drop_if(s, pattern, what):
    count(s, pattern, 1, what)
    try:
        s = cutil.drop_if(s, pattern, flags=re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e))
    say(what)
    return s

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

def repeat(s, pattern, what, n, f):
    count(s, pattern, n, what)
    for _ in range(n):
        try:
            s = _last(s, pattern, f)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    say('%s (%d)' % (what, n))
    return s

# ---- 'autowrite' and 'autowriteall' -- first, since autowrite() reads bt_dontwrite()
t = in_function(t, 'getfile', lambda s: literal(s, ' && autowrite(curbuf, forceit) == FAIL)', ')', 'switching files trying autowrite first'))
t = in_function(t, 'check_changed', lambda s: literal(s, ' && (!(flags & CCGD_AW) || autowrite(buf, forceit) == FAIL))', ')', 'a changed buffer trying autowrite first'))
t = in_function(t, 'nv_gotofile', lambda s: drop_if(s, r'^[ \t]*if \(curbufIsChanged\(\) && curbuf->b_nwindows <= 1\)$', 'gf writing the buffer first'))
t = in_function(t, 'do_bang', lambda s: sub(s, r'^[ \t]*if \(addr_count == 0\)\n[ \t]*\{\n[ \t]*msg_scroll = FALSE;\n[ \t]*autowrite_all\(\);\n[ \t]*msg_scroll = scroll_save;\n[ \t]*\}\n\n?', '', ':! writing all buffers first'))
t = in_function(t, 'ex_stop', lambda s: sub(s, r'^[ \t]*if \(!eap->forceit\)\n[ \t]*\{\n[ \t]*autowrite_all\(\);\n[ \t]*\}\n', '', ':stop writing all buffers first'))
t = literal(t, '(p_awa ? CCGD_AW : 0) | ', '', "'autowriteall' asking check_changed to write", 3)
t = literal(t, 'CCGD_AW | ', '', ':next and the argument list asking check_changed to autowrite', 2)

# ---- 'buftype'
def finfo(s):
    s = literal(s, '(curbuf->b_flags & BF_NOTEDITED) && !bt_dontwrite(curbuf) ?', '(curbuf->b_flags & BF_NOTEDITED) ?', "[Not edited] shown only for a writable 'buftype'")
    s = literal(s, '(curbuf->b_flags & BF_NEW) && !bt_dontwrite(curbuf) ?', '(curbuf->b_flags & BF_NEW) ?', "[New] shown only for a writable 'buftype'")
    return s
t = in_function(t, 'fileinfo', finfo)
def bufwrite(s):
    s = literal(s, ' && !bt_nofilename(buf)', '', "a first :w naming the buffer unless 'buftype' forbids it")
    s = repeat(s, r'^[ \t]*if \(overwriting && bt_nofilename\(curbuf\)\)$', "writing a no-file buffer refused", 3, cutil.fold_never)
    s = repeat(s, r'^[ \t]*if \(nofile_err\)$', "the no-file refusal reported", 2, cutil.fold_never)
    s = literal(s, ' || did_cmd || nofile_err)', ' || did_cmd)', "an autocommand check waiting on the no-file refusal")
    return s
t = in_function(t, 'buf_write', bufwrite)
t = in_function(t, 'buf_copy_options', lambda s: drop_if(s, r"^[ \t]*if \(buf->b_p_bt\[0\] == 'h'\)$", "a help buffer's 'buftype' cleared on copy"))
t = in_function(t, 'changed', lambda s: literal(s, 'if (curbuf->b_may_swap && !bt_dontwrite(curbuf))', 'if (curbuf->b_may_swap)', "the swap file opened only for a writable 'buftype'"))
t = in_function(t, 'readfile', lambda s: repeat(s, r'^[ \t]*if \(!bt_dontwrite\(curbuf\)\)$', "reading checking for a swap file only for a writable 'buftype'", 2, cutil.fold_always))
t = in_function(t, 'open_buffer', lambda s: drop_if(s, r'^[ \t]*if \(bt_nofileread\(curbuf\)\)$', "a no-file 'buftype' skipping the read"))
t = in_function(t, 'do_write', lambda s: literal(s, '(bt_dontwrite_msg(curbuf) || check_fname() == FAIL', '(check_fname() == FAIL', ":w refused for 'buftype'"))
t = in_function(t, 'check_overwrite', lambda s: literal(s, '!bt_nofilename(buf) && ', '', "the overwrite check skipping a no-file buffer"))
t = in_function(t, 'shorten_buf_fname', lambda s: literal(s, ' && !bt_nofilename(buf)', '', "a no-file buffer's name not shortened"))
t = in_function(t, 'buf_spname', lambda s: drop_if(s, r'^[ \t]*if \(bt_nofilename\(buf\)\)$', '[Scratch] for a no-file buffer'))
t = in_function(t, 'edit', lambda s: literal(s, 'if (!bt_prompt(curwin->w_buffer) && stop_insert_mode)', 'if (stop_insert_mode)', "leaving Insert mode differently in a prompt buffer"))
t = in_function(t, 'bufIsChangedNotTerm', lambda s: sub(s, r'return \(!bt_dontwrite\(buf\) \|\| bt_prompt\(buf\)\)\s*&& \(buf->b_changed\);', 'return buf->b_changed;', "a changed buffer judged by 'buftype'"))

# ---- 'jumpoptions'
t = in_function(t, 'setpcmark', lambda s: drop_if(s, r'^[ \t]*if \(jop_flags & JOP_STACK\)$', "the jump list as a stack"))
t = in_function(t, 'cleanup_jumplist', lambda s: literal(s, 'mustfree = !(jop_flags & JOP_STACK);', 'mustfree = TRUE;', "duplicate jumps kept for a stack"))
t = in_function(t, 'didset_string_options', lambda s: sub(s, r'^[ \t]*\(void\)opt_strings_flags\(p_jop, p_jop_values, &jop_flags, TRUE\);\n', '', "startup parsing 'jumpoptions'"))

# ---- 'updatetime': the idle wait did nothing, so it goes
def idle(s):
    s = literal(s, 'if (wtime < 0 && did_start_blocking)', 'if (wtime < 0)', 'a wait with no timeout blocking at once')
    s = sub(s, r'^([ \t]*)if \(wtime >= 0\)\n[ \t]*\{\n[ \t]*wait_time = wtime - elapsed_time;\n[ \t]*\}\n[ \t]*else\n[ \t]*\{\n[ \t]*wait_time = p_ut - elapsed_time;\n[ \t]*\}\n',
            r'\1wait_time = wtime - elapsed_time;\n', "the 'updatetime' idle timeout")
    m = re.search(r'^([ \t]*)if \(wait_time <= 0 && did_call_wait_func\)\n', s, re.M)
    if not m:
        die('inchar_loop -- the expired-wait test was not found')
    ind = m.group(1)
    tail = '\n%s    before_blocking();\n%s    continue;\n%s}\n' % (ind, ind, ind)
    z = s.find(tail, m.end())
    if z < 0 or s.count(tail) != 1:
        die('inchar_loop -- the expired-wait block does not end in before_blocking(); continue;')
    s = s[:m.start()] + '%sif (wait_time <= 0 && did_call_wait_func)\n%s{\n%s    return 0;\n%s}\n' % (ind, ind, ind, ind) + s[z + len(tail):]
    say('CursorHold and before_blocking() after the idle wait')
    # Blocking now starts on the first wait with no timeout, so by the time the
    # loop's exit test runs for one, it has blocked: did_start_blocking was TRUE
    # there, and an interrupted indefinite wait must still return 0 rather than
    # block again.
    s = literal(s, ' || (wtime < 0 && !did_start_blocking))', ')', 'an interrupted indefinite wait returning instead of blocking again')
    return s
t = in_function(t, 'inchar_loop', idle)
t = in_function(t, 'gotchars', lambda s: sub(s, r'^[ \t]*for \(i = 0; i < state\.buflen; \+\+i\)\n[ \t]*\{\n[ \t]*updatescript\(state\.buf\[i\]\);\n[ \t]*\}\n\n?', '', 'typed characters passed to a script file and a swap sync that are both gone'))
def waitret(s):
    for line in ('save_scriptout = scriptout;', 'scriptout = NULL;', 'scriptout = save_scriptout;'):
        s = sub(s, r'^[ \t]*%s\n' % re.escape(line), '', 'wait_return saving and restoring a script file that is never open')
    return s
t = in_function(t, 'wait_return', waitret)
t = in_function(t, 'check_num_option_bounds', lambda s: drop_if(s, r'^[ \t]*if \(p_ut < 0\)$', "'updatetime' kept non-negative"))

# ---- 'buflisted'
t = in_function(t, 'buf_freeall', lambda s: drop_if(s, r'^[ \t]*if \(\(flags & BFA_DEL\) && buf->b_p_bl\)$', 'BufDelete for a listed buffer'))
t = in_function(t, 'buflist_findpat', lambda s: literal(s, 'buf->b_p_bl == find_listed && ', 'find_listed && ', 'a buffer search telling listed from unlisted'))
def bufnew(s):
    s = drop_if(s, r'^[ \t]*if \(\(flags & BLN_LISTED\) && !buf->b_p_bl\)$', 'an existing buffer becoming listed')
    s = sub(s, r'^[ \t]*buf->b_p_bl = \(flags & BLN_LISTED\) \? TRUE : FALSE;\n', '', 'a new buffer recording whether it is listed')
    s = drop_if(s, r'^[ \t]*if \(flags & BLN_LISTED\)$', 'BufAdd for a new listed buffer')
    return s
t = in_function(t, 'buflist_new', bufnew)
t = in_function(t, 'close_buffer', lambda s: sub(s, r'^[ \t]*if \(del_buf\)\n[ \t]*\{\n[ \t]*buf->b_p_bl = FALSE;\n[ \t]*\}\n', '', 'a deleted buffer becoming unlisted'))
t = in_function(t, 'set_rw_fname', lambda s: repeat(s, r'^[ \t]*if \(curbuf->b_p_bl\)$', 'BufDelete and BufAdd around a renamed listed buffer', 2, cutil.fold_never))
t = in_function(t, 'do_ecmd', lambda s: sub(s, r'^[ \t]*else\n[ \t]*\{\n[ \t]*if \(!curbuf->b_help\)\n[ \t]*\{\n[ \t]*set_buflisted\(TRUE\);\n[ \t]*\}\n[ \t]*\}\n', '', 'an edited buffer becoming listed'))
t = sub(t, r'^[ \t]*set_buflisted\((?:TRUE|FALSE)\);\n', '', 'stdin, startup and help buffers setting whether they are listed', 3)

# ---- 'filetype'
t = in_function(t, 'enter_buffer', lambda s: drop_if(s, r'^[ \t]*if \(\*curbuf->b_p_ft == NUL\)$', "entering a buffer with no 'filetype' forgetting FileType"))
t = in_function(t, 'do_ecmd', lambda s: sub(s, r'^[ \t]*curbuf->b_did_filetype = false;\n\n?', '', ':edit forgetting FileType'))
def rf(s):
    s = sub(s, r'^[ \t]*curbuf->b_au_did_filetype = false;\n\n?', '', 'reading forgetting FileType')
    s = drop_if(s, r'^[ \t]*if \(!curbuf->b_au_did_filetype && \*curbuf->b_p_ft != NUL\)$', 'reading firing FileType')
    return s
t = in_function(t, 'readfile', rf)
t = in_function(t, 'did_set_string_option', lambda s: fold_never(s, r'^[ \t]*else if \(varp == &\(curbuf->b_p_ft\)\)$', ":set ft= firing FileType"))
t = in_function(t, 'fix_help_buffer', lambda s: drop_if(s, r'^[ \t]*if \( strcmp\(\(char \*\)\(curbuf->b_p_ft\), \(char \*\)\("help"\)\)  != 0\)$', "a help buffer setting 'filetype' to help"))

open(path, 'w', errors='surrogateescape').write(t)
PY

tools/st.sh dropoptions "$f" jumpoptions updatetime autowrite autowriteall
tools/st.sh dropoptions "$f" --local buflisted buftype filetype

tools/sweep.sh "$f"
# 'buflisted' leaves too little plumbing for droplocal.py: buflist_new() was its
# initialiser, and the folds above took that.  What is left is the field and its
# get_varp() case, and they go by hand.
python3 - "$f" <<'PY'
import re, sys
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()
t, a = re.subn(r'^[ \t]*int[ \t]+b_p_bl;\n', '', t, flags=re.M)
t, b = re.subn(r'^[ \t]*case[^\n]*\bBV_BL\b[^\n]*\n[ \t]*return \(char_u \*\)&\(curbuf->b_p_bl\);\n', '', t, flags=re.M)
if (a, b) != (1, 1):
    sys.exit("  nobufopts    b_p_bl's field and get_varp case matched %d and %d times, expected 1 and 1" % (a, b))
open(path, 'w', errors='surrogateescape').write(t)
print("  nobufopts    'buflisted''s field and get_varp case removed")
PY
tools/st.sh droplocal "$f" b_p_bt b_p_ft

# tools/phaserun.sh sweeps next, then runs pipes/whim62-check.sh.
