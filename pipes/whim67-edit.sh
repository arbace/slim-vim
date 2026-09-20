#!/bin/sh
# Whim phase 67 -- no mouse, no spell plumbing, no write-only flags.
# See WHIM-GOAL.md.
#
# Usage: pipes/whim67-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Three cuts, none of which changes what the editor can do, because none of it
# could happen in the first place.
#
#   THE MOUSE, WHICH CANNOT ARRIVE.  There is no 'mouse' option row, and
#       setmouse(), mch_setmouse(), mouse_has() and p_mouse are all gone, so
#       nothing ever asks a terminal to report mouse events.  What served them
#       goes: is_mouse_key() and the term in the input loop that called it,
#       reset_dragwin()/reset_held_button() with dragwin and held_button,
#       mouse_row/mouse_col and old_mouse_row/old_mouse_col -- a save-and-restore
#       pair that nothing else reads -- the 13 mouse rows of key_names_table, the
#       [MOUSE] entry of the terminal string table, and check_termcode()'s mouse
#       matching.  The 26 nv_cmds rows STAY at nv_error: that table's index is a
#       permutation of its rows, so a removed row renumbers the keys after it.
#
#       ONE REAL CHANGE OF BEHAVIOUR IS BURIED HERE, and it is why the pty check
#       below matters.  `looks_like_mouse_start` is not mouse-specific despite
#       its name: it is set for ANY two-byte `ESC [` termcode whose third byte is
#       not a digit, and it defers the match so that a longer code -- a mouse one
#       -- can win instead.  With no mouse code able to arrive, deferring can only
#       lose, so the fold makes such a code match at once.
#
#   THE SPELL PLUMBING.  spellvars_T is one field, win_line()'s spv parameter is
#       already __attribute__((unused)), and win_update() declares one on the
#       stack only to pass its address twice.
#
#   FOURTEEN WRITE-ONLY STATICS.  gcc never warns about these -- a static that is
#       assigned counts as used -- which is the blind spot that hid can_cindent
#       until phase 64 and struct fields until deadfields.py.  Two of them are a
#       whole function body each, so state_no_longer_safe() and its two calls go
#       with was_safe.
#
#   vim_ignored IS NOT ONE OF THEM, though it looks identical to the detector.
#       Its five sites are `vim_ignored = ftruncate(...)`, `= dup(2)` and
#       `= write(1, ...)`: it exists to swallow warn_unused_result, and removing
#       it ADDS warnings.  A (void) cast does not silence that attribute in gcc.
#
# THE DELTA: none.  No key, command or option changes -- every cut is code that
# nothing could reach.  The probes check the editor still starts, edits and
# writes, and the pty check is what would catch the termcode fold going wrong.
set -eu

work=${1:?usage: whim67-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 - "$f" <<'PY'
TAG = 'nomouse'
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

# ---- the mouse ------------------------------------------------------------------
t = literal(t, ' || (is_mouse_key(n) && n !=   (-((KS_EXTRA) + ((int)(KE_LEFTMOUSE) << 8)))  )', '',
            'the input loop asking whether a key is a mouse key')

t = lines(t, r'reset_dragwin\(\);', 'the two calls that forgot the dragged window', 2)
t = lines(t, r'reset_held_button\(\);', 'the call that forgot the held button')
t = drop_def(t, 'reset_dragwin', 'reset_dragwin, which only cleared a dead pointer')
t = drop_def(t, 'reset_held_button', 'reset_held_button, which only cleared a dead flag')
t = lines(t, r'static win_T \*dragwin = NULL;', 'dragwin itself')
t = lines(t, r'static int[ \t]+held_button = MOUSE_RELEASE;', 'held_button itself')

# mouse_row/col and old_mouse_row/col are a closed loop: saved here, restored there,
# read by nothing else.
t = lines(t, r'static int[ \t]+mouse_row;', 'mouse_row')
t = lines(t, r'static int[ \t]+mouse_col;', 'mouse_col')
t = lines(t, r'static int old_mouse_row;', 'old_mouse_row')
t = lines(t, r'static int old_mouse_col;', 'old_mouse_col')
t = lines(t, r'mouse_row = old_mouse_row;', 'restoring the mouse row')
t = lines(t, r'mouse_col = old_mouse_col;', 'restoring the mouse column')
t = lines(t, r'old_mouse_row = mouse_row;', 'saving the mouse row')
t = lines(t, r'old_mouse_col = mouse_col;', 'saving the mouse column')

# key_names_table: every name a mouse can produce.  MATCH ON THE NAME, not on the
# row's first field: five of them -- DecMouse, JsbMouse, NetMouse, PtermMouse,
# UrxvtMouse -- are written with the key code first and a trailing FALSE, so an
# anchor on `{TRUE,` found 13 of 18 and left the terminal-specific ones behind.
one = re.findall(r'^[ \t]*\{TRUE,[^\n]*\(char_u \*\)\("(\w*(?:Mouse|Drag|Release|Wheel)\w*)"\)[^\n]*\n', t, re.M)
if len(one) != 13:
    die('key_names_table -- %d single-line mouse names, expected 13: %s' % (len(one), ' '.join(one)))
t = sub(t, r'^[ \t]*\{TRUE,[^\n]*\(char_u \*\)\("\w*(?:Mouse|Drag|Release|Wheel)\w*"\)[^\n]*\n', '',
        'the mouse key names: ' + ' '.join(one), 13)
# The terminal-specific five are written across THREE lines -- `{`, `FALSE,`, then
# the code and the name -- so a single-line pattern cannot see them, and matched 13
# of 18.  Anchoring on the name keeps this off every other disabled row.
three = re.findall(r'^[ \t]*\{\n[ \t]*FALSE,\n[ \t]*[^\n]*\(char_u \*\)\("(\w*Mouse\w*)"\)[^\n]*\n', t, re.M)
if len(three) != 5:
    die('key_names_table -- %d three-line mouse names, expected 5: %s' % (len(three), ' '.join(three)))
t = sub(t, r'^[ \t]*\{\n[ \t]*FALSE,\n[ \t]*[^\n]*\(char_u \*\)\("\w*Mouse\w*"\)[^\n]*\n', '',
        'the terminal-specific mouse names: ' + ' '.join(three), 5)
t = sub(t, r'^[ \t]*\{  \(-\(\(KS_MOUSE\) \+ \(\(int\)\( \(\x27X\x27\) \) << 8\)\)\)  ,[^\n]*"\[MOUSE\]"\},\n', '',
        'the [MOUSE] entry of the terminal string table')

def termcode(s):
    s = lines(s, r'int  mouse_index_found = -1;', 'check_termcode remembering a deferred mouse match')
    s = lines(s, r'int     looks_like_mouse_start = FALSE;', 'check_termcode deferring an ESC [ match')
    # The whole `slen == 2 && ESC [` block existed to set that flag, and its only
    # other arm counted the semicolons of a DEC mouse report.
    s = drop_if(s, r"^[ \t]*if \(slen == 2 && len > 2 && termcodes\[idx\]\.code\[0\] == ESC && termcodes\[idx\]\.code\[1\] == '\['\)$",
                'deferring an ESC [ code in case a mouse code is longer')
    s = fold_never(s, r'^[ \t]*if \(looks_like_mouse_start\)$', 'a deferred match winning over a real one')
    s = literal(s, ' && mouse_index_found < 0', '', 'the modifier scan waiting for a deferred mouse match')
    s = fold_never(s, r'^[ \t]*else if \(idx == tc_len && mouse_index_found >= 0\)$', 'falling back to the deferred mouse match')
    # and the test whose body was already empty
    s = sub(s, r'^[ \t]*if \(key_name\[0\] == KS_MOUSE \|\| key_name\[0\] == KS_SGR_MOUSE \|\| key_name\[0\] == KS_SGR_MOUSE_RELEASE\)\n'
               r'[ \t]*\{\n[ \t]*\}\n\n?', '', 'a mouse report being handled by an empty block')
    return s
t = in_function(t, 'check_termcode', termcode)

# ---- the spell plumbing ----------------------------------------------------------
t = literal(t, ', spellvars_T *spv  __attribute__((unused)) )', ')', "win_line's unused spell parameter")
t = lines(t, r'spellvars_T spv;', 'the spell variables win_update kept on the stack')
t = literal(t, 'win_line(wp, lnum, srow, wp->w_height, 0, &spv)', 'win_line(wp, lnum, srow, wp->w_height, 0)', 'the first win_line call')
t = literal(t, 'win_line(wp, lnum, srow, wp->w_height, wp->w_lines[idx].wl_size, &spv)',
            'win_line(wp, lnum, srow, wp->w_height, wp->w_lines[idx].wl_size)', 'the second win_line call')
t = sub(t, r'^typedef struct \{\n[ \t]*int[ \t]+spv_has_spell;\n\} spellvars_T;\n\n?', '', 'spellvars_T itself')

# ---- the write-only statics ------------------------------------------------------
# Each is written and never read.  Where the write is a whole `if` body or a whole
# function, that goes too.
t = lines(t, r'static int[ \t]+did_check_timestamps[ \t]*=[ \t]*FALSE[ \t]*;', 'did_check_timestamps')
t = lines(t, r'did_check_timestamps = FALSE;', 'the three writes to it', 3)
t = lines(t, r'static int[ \t]+did_emsg_syntax;', 'did_emsg_syntax')
t = lines(t, r'did_emsg_syntax = (?:TRUE|FALSE);', 'its two writes', 2)
t = lines(t, r'static int[ \t]+typebuf_was_empty[ \t]*=[ \t]*FALSE[ \t]*;', 'typebuf_was_empty')
t = lines(t, r'typebuf_was_empty = (?:TRUE|FALSE);', 'its two writes', 2)
t = lines(t, r'static volatile sig_atomic_t in_mch_delay = FALSE;', 'in_mch_delay')
t = lines(t, r'in_mch_delay = (?:TRUE|FALSE);', 'its two writes', 2)
t = lines(t, r'static int[ \t]+frame_locked = 0;', 'frame_locked')
t = lines(t, r'frame_locked\+\+;', 'the lock it took')
t = lines(t, r'frame_locked--;', 'the lock it released')
t = lines(t, r'static int[ \t]+swap_exists_did_quit[ \t]*=[ \t]*FALSE[ \t]*;', 'swap_exists_did_quit')
t = lines(t, r'swap_exists_did_quit = TRUE;', 'its one write')
t = lines(t, r'static int[ \t]+did_swapwrite_msg[ \t]*=[ \t]*FALSE[ \t]*;', 'did_swapwrite_msg')
t = lines(t, r'did_swapwrite_msg = FALSE;', 'its one write')
t = lines(t, r'static int[ \t]+autocmd_nested = FALSE;', 'autocmd_nested')
t = lines(t, r'autocmd_nested = ac->nested;', 'its one write')
t = lines(t, r'static volatile sig_atomic_t oldtitle_outdated = FALSE;', 'oldtitle_outdated')
t = lines(t, r'oldtitle_outdated = TRUE;', 'its one write')
t = lines(t, r'static volatile sig_atomic_t deadly_signal = 0;', 'deadly_signal')
t = lines(t, r'deadly_signal = sigarg;', 'the signal number it recorded')

# mr_patternlen's two writes are a whole if/else, so the test goes with them.
t = sub(t, r'^[ \t]*if \(mr_pattern == NULL\)\n[ \t]*\{\n[ \t]*mr_patternlen = 0;\n[ \t]*\}\n'
           r'[ \t]*else\n[ \t]*\{\n[ \t]*mr_patternlen = patlen;\n[ \t]*\}\n', '', "mr_patternlen's if/else")
t = lines(t, r'static size_t[ \t]+mr_patternlen = 0;', 'mr_patternlen')

# was_safe is a whole function body, and that function has two callers.
t = lines(t, r'state_no_longer_safe\("(?:ins_typebuf\(\)|key typed)"\);', 'the two calls that declared the state unsafe', 2)
t = drop_def(t, 'state_no_longer_safe', 'state_no_longer_safe, whose body was one write')
t = lines(t, r'static int[ \t]+was_safe = FALSE;', 'was_safe')
t = lines(t, r'was_safe = (?:is_safe|FALSE);', 'its remaining writes', 2)

open(path, 'w', errors='surrogateescape').write(t)
PY

# tools/phaserun.sh sweeps next, then runs pipes/whim67-check.sh.
