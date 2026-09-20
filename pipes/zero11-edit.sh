#!/bin/sh
# Zero phase 11 -- `:q` quits, and `ZZ` is `ZQ`.  See ZERO-GOAL.md.
#
# Usage: pipes/zero11-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# Phases 6 to 10 took every way to reach a file.  What is left of the filesystem in
# this editor is a REFUSAL: `:q` on a modified buffer answers `E37: No write since
# last change (add ! to override)` and stays.  The protection has no remedy once
# nothing can be written -- there is no `:w` to answer it with and no file the text
# could have come from -- so it is a door that opens onto nothing, and this phase
# takes it.  `:q`, `:q!`, `ZZ` and `ZQ` become one thing.
#
# ONE ANCHOR, AND THE PHASE IS THAT FOLD.  `ex_quit()` is
#
#     if ((check_changed(...)) || (check_changed_any(...))) { not_exiting(...); }
#     else                                                  { getout(0); ... }
#
# and the test is the refusal.  Folding it NEVER keeps the `else` -- "quit" -- and
# is the last reference `check_changed()` has.  FIFTEEN FUNCTIONS THEN GO AND THIS
# FILE NAMES NOT ONE OF THEM (ZERO-GOAL.md rule 1), which is the largest surprise
# the phase has: eleven of the fifteen are not the refusal at all.
# `check_changed_any()`'s tail is "go to the buffer that refused" -- it calls
# `set_curbuf()`, which calls `enter_buffer()` and `win_enter_ext()` -- and after
# whim removed the buffer list and the window commands, THAT TAIL WAS THE LAST
# CALLER OF THE WHOLE SWITCH-BUFFER/SWITCH-WINDOW ISLAND.  THE ISLAND IS A GRAPH AND
# NOT A FAN: only `add_bufnum`, `set_curbuf` and `goto_tabpage_win` are called by
# `check_changed_any` itself and the other eight hang off those, so what the edit
# computes before it folds anything is that every call to any of the eleven is inside
# `check_changed_any` or inside another of the eleven.  After this phase the editor
# has no code for entering a different buffer or a different window at all.
#
# `:q` CAN STILL DECLINE, and that is not this phase's: `text_locked()`,
# `curbuf_locked()` and `before_quit_autocmds()` all return early ABOVE the anchor
# and are untouched.  What goes is the refusal that asked whether the text had been
# saved.
#
# THE BUFFER STILL KNOWS IT IS MODIFIED.  `bufIsChanged` and `curbufIsChanged` keep
# their readers -- CTRL-G still prints `[Modified]`, the status line still draws
# `[+]`, `:set modified?` still answers.  What goes is the refusal, not the state.
#
# THERE ARE NO `'confirm'`-STYLE PROMPTS TO WORRY ABOUT: `grep -cw confirm` on the
# input is 0, whim having removed the dialog layer.  Say it, so that the next reader
# does not go looking for one.
#
# TWO EXTRAS GO WITH THE FOLD, each measured byte-identical in the recording.
#
#   A  TWO STRUCT FIELDS THAT BECOME WRITE-ONLY, WHICH NO TOOL CAN SEE.  This is
#      phase 7's `usefilter` judgement in a smaller shape: tools/deadfields.py
#      removes a field nothing NAMES, and gcc has no warning for a member that is
#      only written.  `win_T.w_topline_was_set`'s only reader was in
#      `enter_buffer()` and `wininfo_S.wi_changelistidx`'s only reader was in
#      `get_winopts()`, and the sweep takes both functions.  THE TEXT THIS LEAVES
#      DOES NOT COMPILE -- two mentions survive inside functions the sweep is about
#      to take -- exactly as pipes/zero7-edit.sh says of its own, and that is stated
#      here rather than discovered by whoever runs the edit alone.
#   B  THE TAIL THAT CANNOT RUN.  After the fold `ex_quit()` ends `int save_exiting
#      = exiting; exiting = TRUE; getout(0); not_exiting(save_exiting);`.
#      `getout()` sets `exiting = TRUE` ITSELF and ends in `mch_exit()`, which never
#      returns, so the first, second and fourth statements are dead and gcc cannot
#      prove it.  Replacing the four with `getout(0);` orphans `not_exiting()`, and
#      `not_exiting()` IS the refusal machinery -- `exiting = save_exiting;
#      settmode(TMODE_RAW);`, the "we changed our mind, put the terminal back" -- so
#      it is this phase's and not tidy.  Check `getout()` before folding this on any
#      other tree: the fold is right only because it sets `exiting` for itself.
#
# `ZZ` IS ALREADY `ZQ` AND STAYS SO.  `nv_Zet` runs `do_cmdline_cmd("q!")` for
# `case 'Z'` AND for `case 'Q'`, identical since phase 6.  After this phase `:q` and
# `:q!` are also identical, so all four spellings are one thing.  THE STRINGS ARE
# NOT REWRITTEN TO `"q"`: it would move `zz_key` and `zq_key` for no gain, and
# `case:zz_key` is phase 6's declaration and must not be re-declared here.
#
# WHAT LEAVES FOR A LATER PHASE TO NOTICE.  `SHM_FILEINFO` is the `'shortmess'` `F`
# letter and its only reader was inside `enter_buffer()`; the sweep takes it, and
# the letter is inert afterwards.  That is the options phase's and the flag strings
# are not touched here.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, as every zero edit since phase 2 does, and the source goes with it as
# $state/old.c.  The check needs both: the exit status of a session that quits with
# unsaved changes is what moves, and no recording can see it.
set -eu

work=${1:?usage: zero11-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero11-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

python3 - "$f" <<'PY'
TAG = 'noquit'
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


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def text_edit(text, old, new, what, n=1):
    """An exact-text replacement, counted file-wide.  Never 'the first one'."""
    k = text.count(old)
    if k != n:
        die('%s -- the text occurs %d times, expected %d: %r'
            % (what, k, n, old[:70]))
    say(what)
    return text.replace(old, new)


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        die('%s is not defined' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


HOW = {'always': cutil.fold_always, 'never': cutil.fold_never, 'drop': cutil.drop_if}


def fold(text, fn, how, pattern, what, n=1):
    """A counted cutil fold, SCOPED TO ONE DEFINITION, as phase 10's is."""
    def edit(s):
        try:
            return HOW[how](s, pattern, n, re.M)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    out = in_function(text, fn, edit)
    say(what)
    return out


# ---- 0. the shape every anchor below was counted against --------------------------
# The fifteen the sweep takes are mostly three each -- a prototype, a definition and
# one call -- and THREE OF THEM ARE NOT, which is what a counted anchor is for.
# `check_changed_any` and `no_write_message_nobang` have NO PROTOTYPE, each being
# defined above its first call, so they are two; `add_bufnum` has no prototype
# either and TWO calls, so it is three for a different reason.  `check_changed` has
# four -- ex_quit calls it once and check_changed_any once -- and `not_exiting`
# four, ex_quit calling it in both arms.
SWEPT = ('no_write_message', 'add_bufnum', 'set_curbuf', 'enter_buffer', 'win_enter',
         'win_enter_ext', 'goto_tabpage_win', 'goto_tabpage_tp', 'get_winopts',
         'find_wininfo', 'buflist_findfpos', 'buflist_getfpos')
BEFORE = {'check_changed': 4, 'not_exiting': 4,
          'check_changed_any': 2, 'no_write_message_nobang': 2,
          'w_topline_was_set': 4,   # the field, one write, and enter_buffer's pair
          'wi_changelistidx': 3,    # the field, find_wininfo's write, get_winopts' read
          'SHM_FILEINFO': 2,        # 'shortmess' F, read once inside enter_buffer
          'bufIsChanged': 10, 'curbufIsChanged': 7, 'bufIsChangedNotTerm': 3,
          'exiting': 17, 'buf_spname': 5, 'open_buffer': 5,
          'curbuf_locked': 7, 'text_locked': 6, 'before_quit_autocmds': 2,
          'p_ro': 2, 'p_ur': 2,     # 'readonly' and 'undoreload': the options phase's
          'read_cmd_fd': 12,        # the terminal's: fill_input_buf, mch_settmode
          'vim_fsync': 3, 'scriptin': 8, 'redir_fd': 6}
BEFORE.update(dict.fromkeys(SWEPT, 3))
for name, want in sorted(BEFORE.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions, expected %d -- the anchors below were counted '
            'against a different file' % (name, k, want))
say('check_changed 4, not_exiting 4, check_changed_any 2 and the twelve the '
    'sweep reads from it -- the file the one fold was counted against')

# THE INVARIANT, COMPUTED BEFORE ANYTHING IS FOLDED.  Every one of the eleven
# functions that are NOT the refusal goes because check_changed_any()'s tail is
# their last caller, so that is required rather than assumed: the single surviving
# call to each must be inside check_changed_any's definition.
ISLAND = ('add_bufnum', 'set_curbuf', 'enter_buffer', 'win_enter', 'win_enter_ext',
          'goto_tabpage_win', 'goto_tabpage_tp', 'get_winopts', 'find_wininfo',
          'buflist_findfpos', 'buflist_getfpos')
# THE ISLAND IS A GRAPH, NOT A FAN, and a check that required every one of the eleven
# to be called BY check_changed_any would fail on a correct phase: only add_bufnum,
# set_curbuf and goto_tabpage_win are, and the other eight hang off those.  What is
# true, and what every fold below rests on, is that every call to any of the eleven
# is inside check_changed_any or inside another of the eleven -- so the whole island
# is reachable from that one tail and from nowhere else.
spans = {}
for name in ISLAND + ('check_changed_any',):
    spans[name] = cutil.find_definition(t, name)
    if not spans[name]:
        die('%s is not defined' % name)
for name in ISLAND:
    own = spans[name]
    stray, calls = [], 0
    for m in re.finditer(r'\b%s\b' % name, t):
        if own[0] <= m.start() < own[1]:
            continue          # inside its own definition
        line = t[t.rfind('\n', 0, m.start()) + 1:t.index('\n', m.start())].strip()
        if re.match(r'^static\b.*\b%s\(.*\);$' % name, line):
            continue          # its prototype
        calls += 1
        if not any(a <= m.start() < z for a, z in spans.values()):
            stray.append(t.count('\n', 0, m.start()) + 1)
    if not calls or stray:
        die('%s has %d call site(s) and %d of them are outside check_changed_any '
            'and the island (first at line %s); the switch-buffer island does not '
            'hang off that one tail after all'
            % (name, calls, len(stray), stray[0] if stray else '-'))
say('every call to add_bufnum, set_curbuf, enter_buffer, win_enter, win_enter_ext, '
    'goto_tabpage_win, goto_tabpage_tp, get_winopts, find_wininfo, buflist_findfpos '
    'and buflist_getfpos is inside check_changed_any or inside another of the '
    'eleven -- its tail, "go to the buffer that refused", is the last caller of the '
    'whole switch-buffer/switch-window island, and that, and nothing weaker, is why '
    'the one fold below takes eleven functions nobody would predict')

# ---- 1. the anchor: the refusal folds never ------------------------------------------
# `if (F) { A } else { C }`, so the `else` arm -- getout(0) -- is what is kept.  The
# polarity is the phase: the test is TRUE only when the buffer is changed, and
# keeping the else is "quit".
t = fold(t, 'ex_quit', 'never',
         r'^    if \(\(check_changed\(wp->w_buffer, \(eap->forceit \? CCGD_FORCEIT : 0\) \| CCGD_EXCMD\)\) \|\| \(check_changed_any\(eap->forceit, TRUE\)\)\)$',
         "ex_quit: the refusal folds NEVER, so `:q` takes the else arm and quits -- "
         'this one fold is the phase, and it is check_changed()\'s last reference')

# ---- 2. extra B: the tail that cannot run --------------------------------------------
# getout() sets `exiting = TRUE` for itself and ends in mch_exit(), which never
# returns.  So the save, the set and the restore are all dead, and gcc cannot prove
# it.  not_exiting() is then uncalled and the sweep's.
t = text_edit(t,
              '    int save_exiting = exiting;\n'
              '    exiting = TRUE;\n'
              '    getout(0);\n'
              '    not_exiting(save_exiting);\n',
              '    getout(0);\n',
              "ex_quit's tail: getout() sets `exiting = TRUE` itself and ends in "
              'mch_exit(), which never returns, so the save, the set and the '
              'restore are dead -- and not_exiting(), which was the whole of "we '
              'changed our mind, put the terminal back", has no caller left')
if mentions(t, 'not_exiting') != 2:
    die('not_exiting has %d mentions, expected 2 -- its prototype and its '
        'definition, for the sweep' % mentions(t, 'not_exiting'))

# ---- 3. extra A: two fields that become write-only ------------------------------------
# NOTHING SEES EITHER OF THESE.  tools/deadfields.py removes a field nothing NAMES,
# and a field that is only written is still named; gcc has no warning for one.  So
# the declaration and the surviving write go here, by hand, and the READER of each
# goes with the function the sweep takes.
#
# THE TEXT THIS LEAVES DOES NOT COMPILE, and that is said out loud rather than
# discovered: `enter_buffer()` still reads w_topline_was_set and `get_winopts()`
# still reads wi_changelistidx, and both functions are the sweep's.  It is phase 7's
# shape and phases 6, 8 and 10 leave the same kind of intermediate.
for fld, reader in (('w_topline_was_set', 'enter_buffer'),
                    ('wi_changelistidx', 'get_winopts')):
    span = cutil.find_definition(t, reader)
    if not span or fld not in t[span[0]:span[1]]:
        die('%s is not named inside %s, and the sweep taking that function is the '
            'whole reason this field becomes write-only' % (fld, reader))
t = text_edit(t, '    bool        w_topline_was_set;\n', '',
              "win_T.w_topline_was_set: its only reader is inside enter_buffer(), "
              'which the sweep takes -- so the field is write-only and nothing sees '
              'it')
t = text_edit(t, '    wp->w_topline_was_set = true;\n', '',
              'and its one surviving write, in set_topline()')
t = text_edit(t, '    int         wi_changelistidx;\n', '',
              'wininfo_S.wi_changelistidx: its only reader is inside get_winopts(), '
              'swept with the rest of the island')
t = text_edit(t, '        wip->wi_changelistidx = win->w_changelistidx;\n', '',
              'and its one surviving write, in find_wininfo() -- which the sweep '
              'takes too, so this line is removed for what it says and not for what '
              'it costs')

# ---- what the sweep is handed, as a count rather than as trust -------------------------
AFTER = {'check_changed': 3,        # prototype, definition, check_changed_any's call
         'not_exiting': 2,
         'w_topline_was_set': 2, 'wi_changelistidx': 1,
         'bufIsChanged': 10, 'curbufIsChanged': 7, 'bufIsChangedNotTerm': 3,
         'curbuf_locked': 7, 'text_locked': 6, 'before_quit_autocmds': 2,
         'p_ro': 2, 'p_ur': 2, 'read_cmd_fd': 12,
         'vim_fsync': 3, 'scriptin': 8, 'redir_fd': 6}
for name, want in sorted(AFTER.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions after the cut, expected %d' % (name, k, want))
say('the cut is done: check_changed 3 -- its prototype, its definition and the '
    'one call inside check_changed_any, which is where the sweep starts -- '
    'not_exiting 2, and read_cmd_fd 12, vim_fsync 3, scriptin 8 and redir_fd 6 '
    "untouched, each of them a later phase's")

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  noquit       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  noquit       the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: a session that types text and then quits with nothing after it exits 1 on that binary and 0 here, and no recording can see it"

# tools/phaserun.sh sweeps next, then runs pipes/zero11-check.sh.
