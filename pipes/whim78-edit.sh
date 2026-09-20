#!/bin/sh
# Whim phase 78 -- empty functions, write-only counters, and the window id.
# See WHIM-GOAL.md.
#
# Usage: pipes/whim78-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Three unrelated kinds of leftover, all of them invisible to the compiler and so to
# every sweep this pipeline runs.  A fourth kind -- the constant-return predicates --
# was split out into its own phase after the survey showed it is not one shape but
# several: only about twenty of the twenty-nine sit in a foldable `if`, the rest
# needing term-level or expression edits, and one of them is a function pointer in an
# option table row that must not be touched at all.  Bundling them here would have
# repeated the shape that cost phase 75 eight iterations.
#
# (1) FIFTEEN FUNCTIONS WITH EMPTY BODIES, 49 call sites.  Each was emptied by an
#     earlier phase and left with its callers in place; the call is a no-op that the
#     compiler still emits.  EVERY ONE OF THE 49 IS A BARE STATEMENT -- checked, not
#     assumed: none appears in an if, an assignment or any larger expression, so a
#     line removal cannot corrupt a condition.  That was the trap in phase 75, where
#     ins_apply_autocmds calls were invisible to a regex anchored on `apply_autocmds`.
#
#     nv_nop IS NOT AMONG THEM.  It is empty by design -- the nv_cmds row for KE_NOP
#     -- and nvidxcheck.py requires nv_cmd_idx[] to stay a permutation of the rows.
#
# (2) SIX WRITE-ONLY STATICS.  gcc never warns: assigning to a static counts as using
#     it, which is the can_cindent shape.  Each is incremented and decremented and
#     never read:
#
#       autocmd_blocked         its reader is_autocmd_blocked went in phase 75
#       autocmd_no_enter        ++/-- in create_windows
#       autocmd_no_leave        ++/-- in create_windows
#       redrawing_for_callback  ++/-- in redraw_after_callback
#       prevwin                 written once in win_enter_ext, read nowhere since 75
#       last_win_id             only `w_id = ++last_win_id`, and w_id goes below
#
#     TWO OTHERS ARE FLAGGED BY THE SAME SCAN AND MUST NOT BE TOUCHED.
#     breakcheck_count is READ by `if (++breakcheck_count >= BREAKCHECK_SKIP)`, and
#     vim_ignored is the deliberate sink for discarded return values, kept on purpose
#     in phase 67.  A scanner that counts `++x` as a write and cannot see the read in
#     `x = call()` reports both as write-only.  They are not.
#
#     block_autocmds() and unblock_autocmds() become EMPTY once the counter goes, and
#     they stay that way: they have eight live call sites, one of them deliberately
#     unpaired in deathtrap() -- the process is dying and never unblocks -- so
#     removing calls would touch a signal handler for no gain.
#
# (3) THE WINDOW ID.  With one window, curwin->w_id is a constant, so both
#     `if (is_state.winid != curwin->w_id)` guards in getcmdline_int can never fire.
#     Folding them makes incsearch_state_T.winid write-only, which makes w_id
#     write-only, which makes last_win_id and LOWEST_WIN_ID unread.  One chain.
#     init_incsearch_state keeps a live caller at the top of getcmdline_int, so the
#     function stays; only the two re-initialising guards go.
#
#     The two guards are spelled at DIFFERENT INDENTS -- one at eight spaces, one at
#     twelve -- so they are matched by a regex, not by a literal with a count of two.
#
# (4) ONE DEAD FIELD the field sweep cannot see: cmdarg_T.prechar.  deadfields.py
#     exempts every field of a type that has a positional initialiser anywhere, and
#     cmdarg_T has `cmdarg_T ca = { 0 };` -- which supplies one value and zero-fills
#     the rest, so removing prechar cannot overflow it.
#
#     termrequest_T.tr_start WAS on this list and is NOT removed.  It has a single
#     identifier mention, its declaration, which is what made an audit call it dead --
#     but termrequest_T is positionally initialised three times as {STATUS_GET, -1},
#     and that -1 IS tr_start.  A positional initialiser names nothing, so counting
#     identifiers cannot see the use.  That is the very reason deadfields exempts such
#     types, and the exemption was recorded during the audit and then ignored.
#
# THE DELTA: none expected.  An empty function called or not called does the same
# nothing; a counter nobody reads has no effect; and the two winid guards can never
# fire.  Declared empty, left for whimdelta.sh to correct.
set -eu

work=${1:?usage: whim78-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 - "$f" <<'PY'
TAG = 'nostubs'
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

def lines(text, pattern, what, n=1):
    rx = re.compile(r'^[ \t]*' + pattern + r'[ \t]*\n', re.M)
    k = len(rx.findall(text))
    if k != n:
        die('%s -- %d lines match, expected %d' % (what, k, n))
    say(what)
    return rx.sub('', text)

def fold_never(text, fn, pattern, what, n=1):
    def edit(s):
        try:
            return cutil.fold_never(s, pattern, n, re.M)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    out = in_function(text, fn, edit)
    say(what)
    return out

def body_of(text, name):
    sp = cutil.find_definition(text, name)
    if not sp:
        die('%s is not defined' % name)
    s = text[sp[0]:sp[1]]
    return s[s.index('{\n') + 2:s.rindex('}')]

# ---- the empty functions ----------------------------------------------------------
EMPTY = ['clear_chartabsize_arg', 'may_trigger_modechanged',
         'may_trigger_win_scrolled_resized', 'out_flush_check', 'add_b0_fenc',
         'set_b0_dir_flag', 'pum_may_redraw', 'ml_setname', 'ml_preserve',
         'trigger_undo_ftplugin', 'set_init_lang_env',
         'set_init_default_printencoding', 'set_init_3', 'mch_new_shellsize',
         'mch_early_init']

# Every body must be empty and every call a bare statement.  Both are asserted rather
# than trusted: an emptied-since function would make the removal a behaviour change,
# and a call inside a condition would leave a syntax error.
for fn in EMPTY:
    if body_of(t, fn).strip() != '':
        die('%s is no longer empty -- removing its calls would change behaviour' % fn)
if body_of(t, 'nv_nop').strip() != '':
    die('nv_nop is no longer empty; it is the nv_cmds KE_NOP row and must stay empty')

total = 0
for fn in EMPTY:
    bare = re.compile(r'^[ \t]*(?:\(void\))?%s\([^;\n]*\);[ \t]*\n' % re.escape(fn), re.M)
    allref = [m for m in re.finditer(r'\b%s\b' % re.escape(fn), cutil.blank(t))]
    n_bare = len(bare.findall(t))
    # every mention that is not the prototype, the definition or a bare call is a use
    # this phase cannot simply delete
    n_proto = len(re.findall(r'^static [^\n]*\b%s\(' % re.escape(fn), t, re.M))
    n_defn = len(re.findall(r'^%s\(' % re.escape(fn), t, re.M))
    if len(allref) != n_bare + n_proto + n_defn:
        die('%s has %d mentions but only %d bare calls (+%d proto +%d defn) -- one is '
            'inside an expression and a line removal would corrupt it'
            % (fn, len(allref), n_bare, n_proto, n_defn))
    t = bare.sub('', t)
    total += n_bare
say('every call to the %d functions that do nothing (%d sites)' % (len(EMPTY), total))

# ---- the window id ----------------------------------------------------------------
# Two guards, at different indents, so this is a counted regex and not a literal.
t = fold_never(t, 'getcmdline_int',
               r'^[ \t]*if \(is_state\.winid != curwin->w_id\)$',
               'the command line re-initialising incremental search for another window', 2)
t = in_function(t, 'init_incsearch_state', lambda s: lines(
    s, r'is_state->winid = curwin->w_id;', 'recording which window the search started in'))
t = lines(t, r'int[ \t]+winid;', 'the field that recorded it')
t = in_function(t, 'win_alloc', lambda s: lines(
    s, r'new_wp->w_id = \+\+last_win_id;', 'numbering the one window'))
t = lines(t, r'int[ \t]+w_id;', 'the number it was given')
t = lines(t, r'static int last_win_id = LOWEST_WIN_ID - 1;', 'the counter behind it')
t = lines(t, r'enum \{ LOWEST_WIN_ID = 1000 \};', 'and where the numbering started')

# ---- the write-only counters -------------------------------------------------------
t = in_function(t, 'block_autocmds', lambda s: lines(s, r'\+\+autocmd_blocked;', 'blocking autocommands'))
t = in_function(t, 'unblock_autocmds', lambda s: lines(s, r'--autocmd_blocked;', 'and unblocking them'))
t = lines(t, r'static int[ \t]+autocmd_blocked = 0;', 'the count nothing reads')

for v in ('autocmd_no_enter', 'autocmd_no_leave'):
    t = in_function(t, 'create_windows', lambda s, w=v: lines(s, r'\+\+%s;' % w, 'startup suppressing %s' % w))
    t = in_function(t, 'create_windows', lambda s, w=v: lines(s, r'--%s;' % w, 'and restoring it'))
t = lines(t, r'static int[ \t]+autocmd_no_enter  = FALSE ;', 'the enter flag')
t = lines(t, r'static int[ \t]+autocmd_no_leave  = FALSE ;', 'the leave flag')

t = in_function(t, 'redraw_after_callback', lambda s: lines(s, r'\+\+redrawing_for_callback;', 'marking a callback redraw'))
t = in_function(t, 'redraw_after_callback', lambda s: lines(s, r'--redrawing_for_callback;', 'and unmarking it'))
t = lines(t, r'static int redrawing_for_callback  = 0 ;', 'the mark nothing reads')

t = in_function(t, 'win_enter_ext', lambda s: lines(s, r'prevwin = curwin;', 'remembering the previous window'))
t = lines(t, r'static win_T[ \t]+\*prevwin  = NULL ;', 'the window nothing looks back at')

# ---- the two fields the field sweep cannot see -------------------------------------
t = lines(t, r'int[ \t]+prechar;', 'cmdarg_T.prechar')

# termrequest_T.tr_start is NOT REMOVED, and the reason is worth recording.
#
# An earlier audit listed it as dead because it has exactly one identifier mention --
# its own declaration.  But termrequest_T is POSITIONALLY INITIALISED three times:
#
#     static termrequest_T crv_status = {STATUS_GET, -1};
#     static termrequest_T u7_status  = {STATUS_GET, -1};
#     static termrequest_T xcc_status = {STATUS_GET, -1};
#
# and that `-1` IS tr_start.  A positional initialiser names nothing, so counting
# identifiers cannot see it -- which is exactly why deadfields.py exempts every field
# of a type that has one.  Removing the field made all three initialisers overflow
# ("excess elements in struct initializer") and phasecheck stopped the phase.
#
# cmdarg_T is the other case and is safe: its only positional initialiser is
# `cmdarg_T ca = { 0 };`, which supplies one value and zero-fills the rest, so losing
# prechar cannot overflow it.  The distinction is whether the initialiser supplies
# enough values to reach the field being removed.

open(path, 'w', errors='surrogateescape').write(t)
PY

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim78-check.sh.
