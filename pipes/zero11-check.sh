#!/bin/sh
# Zero phase 11, the check -- `:q` quits, and nothing refuses any more.
# See pipes/zero11-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero11-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero11-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from: the left-hand side of every
# before-and-after count, and of every probe.
#
# SIX THINGS ARE PROVED HERE, and the fifth is the only one that can say what this
# phase actually did to the editor.
#
# 1. THE CUT, WHICH IS THE SWEEP'S AND NOT THE EDIT'S.  SIXTEEN functions go and the
#    edit names none of them, from ONE fold.  ELEVEN OF THE SIXTEEN ARE A SURPRISE
#    and are the largest part of the phase: `check_changed_any()`'s tail is "go to
#    the buffer that refused", and after whim removed the buffer list and the window
#    commands that tail was the last caller of the whole switch-buffer/switch-window
#    island.  The list below is a RECORDING of what the sweep did, which is the only
#    place a list of removed names belongs (ZERO-GOAL.md rule 1), and the COUNT is
#    asserted beside it -- 1,742 definitions to 1,726 -- because a check written
#    from ZERO-PLAN.md's three names would pass while the island silently went.
#
#    THE TRAPS, ALL MEASURED, that make a copied loop wrong here:
#      * `bufIsChanged` GOES 10 -> 7 AND MUST NOT GO TO 0, and `curbufIsChanged`
#        does not move at all.  The buffer still knows it is modified: CTRL-G still
#        prints `[Modified]`, the status line still draws `[+]`, `:set modified?`
#        still answers.  What went is the refusal, not the state.
#      * `text_locked`, `curbuf_locked` and `before_quit_autocmds` DO NOT MOVE.  All
#        three return early ABOVE the anchor, so `:q` can still decline -- just not
#        for the reason this phase removed.
#      * `open_buffer` goes 5 -> 4, `buf_spname` 5 -> 4 and `exiting` 17 -> 13.
#        Phase 9's brief pinned `open_buffer` at 5 and phase 10's check at 5; both
#        were right there and would fail here, `enter_buffer()` having been one of
#        its four callers.
#      * `p_wh` LOOKS WRITE-ONLY AND IS NOT.  It goes 4 -> 2 -- the two reads in
#        `win_enter_ext`'s callee went with the island -- and the two that are left
#        are its declaration, which carries the initialiser, and one real reader in
#        the frame layer.  A "uses - writes - 1 <= 0" scan reports it and is wrong.
#      * `SHM_FILEINFO` leaves, and it is the `'shortmess'` `F` letter.  The letter
#        is accepted and inert afterwards; that is the options phase's and the flag
#        strings are not touched here.
#
# 2. NOTHING IS LEFT WRITE-ONLY, AND IT IS COMPUTED ON BOTH TEXTS.  A file-scope
#    static that is assigned and never read draws no warning, deadsweep.py acts on
#    warnings, and nothing else here looks -- phase 10 had to take `readonlymode` by
#    hand for exactly that shape.  So the scan runs on the source this phase was
#    handed as well as on the one it made, and the two answers must be the SAME SET
#    and must be exactly `vim_ignored`, upstream's sink for a return value that is
#    deliberately ignored.  It finding something either side is what makes an empty
#    answer a scan failure rather than a phase succeeding.  `p_wh` is what the
#    OBVIOUS scan gets wrong and this one does not: a "uses - writes - 1 <= 0" count
#    charges its initialiser to the writes.  The TWO STRUCT FIELDS that did become
#    write-only are the edit's extra A and are already gone -- no warning and no tool
#    sees a member that is only written.
#
# 3. THE LINE AGAINST THE PHASES AFTER THIS ONE, stated as counts so that reaching
#    into one would fail here rather than widen quietly: `p_ro` 2 and `p_ur` 2 WITH
#    their option rows (the options phase's), `read_cmd_fd` 12 (the terminal's),
#    and `scriptin` 8, `redir_fd` 6 and `vim_fsync` 3 (the FILE* phase's), with
#    `fclose`, `getc`, `putc` and `fsync` asserted STILL undefined.
#
# 4. THE ENUMERATORS, DUMPED EITHER SIDE.  Twelve go -- the four `CCGD_`, the two
#    `DOBUF_`, `SHM_FILEINFO` and the five `WEE_` -- and NOTHING RENUMBERS, because
#    typereach.py takes whole anonymous definitions and a whole definition leaving
#    takes no survivor's value with it.  That is the opposite of phase 10, where 85
#    moved, and it is worth the four seconds either side to say so rather than
#    assume it.
#
# 5. THE PROBES, ON BOTH BINARIES, BECAUSE THE CORPUS CANNOT SEE THE EXIT STATUS.
#    The one case it sees is `quit_modified`, and it ends with a trailing `:q!` --
#    which quits the OLD binary too, so the status is 0 either side and what the
#    recording holds is a message that changed.  `q_alone` is the probe that is not:
#    `ihello<Esc> :set nopaste :q` AND NOTHING AFTER IT.  The old binary draws
#    `E37: No write since last change (add ! to override)`, runs out of stdin,
#    prints `Vim: Finished.` and exits 1; this one quits on the `:q` and exits 0.
#    That difference -- 1 to 0 -- is the whole phase measured from outside, and no
#    recording can see it.
#
#    THE MUST-NOT-MOVE HALF IS REQUIRED TO BE DOING SOMETHING, or "it did not move"
#    is two failures agreeing: `ctrl_g` must say `[Modified]`, `editing` must say
#    `alpha`, `cquit` must exit 1 on both, `q_clean` must exit 0 on both with no E37
#    anywhere -- it is `:q` on an UNMODIFIED buffer, which took the else arm before
#    this phase and takes it now -- and `zz_key`/`zq_key` must leave the same screen.
#
# 6. A REAL TERMINAL, because every probe above went through a pipe.  On a pty the
#    old binary answers E37 to `:q` and is still running, so the `:q!` after it
#    reaches the command line; this one draws no E37 at all.  THE OPPOSITE PAIR --
#    "the `:q!` did not reach the new binary" -- IS NOT ASSERTED, and it is a race:
#    once the editor has quit the pty leaves raw mode and whether the trailing
#    keystrokes are echoed back depends on how fast the process exits.  What the `:q`
#    quit is `q_alone`'s to say, by its exit status through a pipe.  An ordinary
#    editing session beside it must be identical either side.
#
# A record is built the way `zcases` builds one and scrubbed the same way
# (tools/zrec.py).  tools/zstream.py's session() is not called directly because this
# check needs the raw stream, the exit status and the snapshot count beside the
# screens.
set -eu

work=${1:?usage: zero11-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero11-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 1. what the sweep took, recorded -----------------------------------------------
# SIXTEEN functions, none of them named by the edit, from one fold.  The first five
# are the refusal; the eleven after them are the switch-buffer/switch-window island
# that hung off check_changed_any()'s tail and that nobody predicted.
for gone in check_changed check_changed_any no_write_message no_write_message_nobang \
            not_exiting \
            add_bufnum set_curbuf enter_buffer win_enter win_enter_ext \
            goto_tabpage_win goto_tabpage_tp get_winopts find_wininfo \
            buflist_findfpos buflist_getfpos \
            w_topline_was_set wi_changelistidx SHM_FILEINFO; do
    n=$(grep -cw -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  noquit       '$gone' still has $n mentions"; exit 1; }
done
# The three literals that lose their last speaker, and they are the whole message
# set of the refusal.  E162 was check_changed_any()'s, the other two check_changed's.
for gone in 'E37: No write since last change (add ! to override)' \
            'E37: No write since last change' \
            'E162: No write since last change for buffer '; do
    n=$(grep -cF -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  noquit       the string '$gone' still has $n mentions"; exit 1; }
done
echo "  noquit       sixteen functions, two struct fields, SHM_FILEINFO and the three 'No write since last change' literals at 0 mentions -- all of it the sweep's but the two fields, and the edit named not one function"

# --- 2. and everything that must NOT be at zero -------------------------------------
python3 - "$f" "$state/old.c" <<'PY'
import re, sys
sys.path.insert(0, 'tools')
import create_cmdidxs
import cutil
import funcreach
TAG = 'noquit'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
fail = []


def count(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


# THE COUNT, AS THE PHASE'S OWN ASSERTION.  One fold takes sixteen functions, eleven
# of which no plan predicted, so "the named ones went" is not the check -- the
# number is.  A phase that reached further, or less far, fails here first.
n_old = len(funcreach.definitions(old, cutil.blank(old)))
n_new = len(funcreach.definitions(new, cutil.blank(new)))
if (n_old, n_new) != (1742, 1726):
    fail.append('the function count went %d -> %d, expected 1742 -> 1726: one fold '
                'takes SIXTEEN, and eleven of them are the switch-buffer island'
                % (n_old, n_new))

# THE BARE WORDS, each with the reason it is not zero.  A loop that wanted zero for
# any of these would fail on a correct phase.
KEPT = {'bufIsChanged': 7,        # the buffer still KNOWS it is modified
        'curbufIsChanged': 7,     # and this does not move at all
        'bufIsChangedNotTerm': 3,
        'text_locked': 6,         # `:q` can still decline, above the anchor
        'curbuf_locked': 7,
        'before_quit_autocmds': 2,
        'getout': 7,              # what the fold kept
        'mch_exit': 8,            # which getout() ends in, and never returns from
        'exiting': 13,            # 17 before: the save, the set and the restore
        'buf_spname': 4,          # 5 before: check_changed_any's E162 went
        'open_buffer': 4,         # 5 before: enter_buffer was one of four callers
        'fileinfo': 3,            # CTRL-G, g CTRL-G and the startup message
        'check_fname': 3,         # E32's speaker, still called by the `%` register
        'p_ur': 2, 'p_ro': 2,     # 'undoreload' and 'readonly': the options phase's
        'read_cmd_fd': 12,        # the terminal's: fill_input_buf, mch_settmode
        'vim_fsync': 3,           # ui_write's, and the FILE* phase's
        'scriptin': 8, 'redir_fd': 6,
        'msg_scrolled_ign': 2,    # phase 9's leftover, read-only, and it does not move
        'nv_error': 46,           # the 'Q' row phase 4 pointed here
        'p_wh': 2}                # see below: this is NOT write-only
for name, want in sorted(KEPT.items()):
    k = count(new, name)
    if k != want:
        fail.append('%s has %d mentions, expected %d -- %s'
                    % (name, k, want, 'this phase reached too far'
                       if k < want else 'something survived that should not have'))

# `p_wh` LOOKS WRITE-ONLY AND IS NOT, and this is the assertion that says so rather
# than a comment hoping someone reads it.  Its two survivors are the declaration,
# which carries the initialiser, and one real reader in the frame layer.
if not re.search(r'^static long\s+p_wh = 1L;$', new, re.M):
    fail.append("p_wh lost its initialising declaration, which is the half of its "
                'two mentions that makes it look write-only')
if not re.search(r'^\s*m = p_wh \+ ', new, re.M):
    fail.append('p_wh lost its one real reader, and a "uses - writes - 1 <= 0" scan '
                'would then be right about it for the first time')

# NO FILE-SCOPE STATIC BECOMES WRITE-ONLY, computed rather than asserted by name.
# Phase 10 had to remove `readonlymode` by hand for exactly this shape -- a static
# that is assigned and never read draws no warning, deadsweep.py acts on warnings,
# and nothing else here looks -- so the scan is run on BOTH texts and the two answers
# must be the same set.  That is what makes it a check rather than a hope: it finds
# something in each (`vim_ignored`, upstream's sink for a return value that is
# deliberately ignored, two writes and no read in the input as well), so an empty
# answer would be the scan failing rather than the phase succeeding.
#
# THE OBVIOUS SCAN IS WRONG AND `p_wh` IS WHAT IT GETS WRONG.  A "uses - writes - 1
# <= 0" count reports it, because its declaration carries the initialiser and the
# formula charges that to the writes; p_wh keeps one real reader.  So the
# declaration's own mention is excluded by POSITION here, not by arithmetic.
DECL = re.compile(r'^static\s+[A-Za-z_][\w \t*]*?\b(\w+)\s*(=[^;]*)?;$', re.M)
ASSIGN = re.compile(r'\s*(\)\s*)?([-+|&^*/]|<<|>>)?=[^=]')


def write_only(text):
    out = []
    for m in DECL.finditer(text):
        name = m.group(1)
        reads = writes = 0
        for x in re.finditer(r'\b%s\b' % name, text):
            if m.start() <= x.start() < m.end():
                continue                      # the declaration itself
            if ASSIGN.match(text[x.end():x.end() + 4]):
                writes += 1
            else:
                reads += 1
        if writes and not reads:
            out.append(name)
    return sorted(out)


wo_old, wo_new = write_only(old), write_only(new)
if wo_new != wo_old or wo_new != ['vim_ignored']:
    fail.append('the write-only scan reports %s where the input reports %s; both '
                'must be exactly vim_ignored, which is upstream\'s sink for an '
                'ignored return value and was write-only before this phase'
                % (' '.join(wo_new) or 'nothing', ' '.join(wo_old) or 'nothing'))

# THE OTHER DIRECTION, which is where a check copied from phases 6 to 10 fails.
# Every one of those five asserts `E37: No write since last change` SURVIVES and
# names check_changed as the `:q` phase's.  This is the `:q` phase.
if 'No write since last change' in new:
    fail.append('E37 or E162 survives, and this phase removes the refusal that said '
                'them -- phases 6 to 10 all assert the opposite, which is why none '
                'of them can share a stage with this one')
if 'No write since last change' not in old:
    fail.append('the input did not refuse, so this phase is being checked against a '
                'file it was not written for')
# `[Modified]` and `[No Name]` are the opposite way round: the state survives.
for lit, want in (('[Modified]', 1), ('[No Name]', 2), ('E32: No file name', 1)):
    if new.count(lit) != want:
        fail.append('%r occurs %d times, expected %d -- the buffer still knows it is '
                    'modified and still has no name; what went is the refusal'
                    % (lit, new.count(lit), want))

# ex_quit is one statement and a getout() now, with no test left between
# before_quit_autocmds() and it.
span = cutil.find_definition(new, 'ex_quit')
body = new[span[0]:span[1]] if span else ''
if not body:
    fail.append('ex_quit is gone, and this phase folds it rather than removing it')
if 'save_exiting' in body or 'exiting = TRUE' in body:
    fail.append("ex_quit still saves and sets `exiting`: getout() does both itself "
                'and never returns, which is why extra B is honest')
if body.count('getout(0);') != 1:
    fail.append('ex_quit does not end in exactly one getout(0);: %r' % body[-120:])
for kept in ('text_locked', 'curbuf_locked', 'before_quit_autocmds'):
    if kept not in body:
        fail.append('ex_quit no longer calls %s, and all three early returns are '
                    'above the anchor and not this phase\'s' % kept)

# `ZZ` IS `ZQ` AND THE STRINGS ARE NOT REWRITTEN.  nv_Zet ran do_cmdline_cmd("q!")
# for both since phase 6; rewriting either to "q" would move zz_key and zq_key for
# no gain, and case:zz_key is phase 6's declaration.
span = cutil.find_definition(new, 'nv_Zet')
zet = new[span[0]:span[1]] if span else ''
if zet.count('do_cmdline_cmd((char_u *)"q!")') != 2:
    fail.append('nv_Zet does not run `q!` for both ZZ and ZQ: it has since phase 6 '
                'and rewriting either string would move a record phase 6 declared')

# THE TABLE.  No row goes and no nv_cmds[] row is touched.
rows = re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M)
got = create_cmdidxs.names(sys.argv[1])
try:
    create_cmdidxs.names_from_cmdnames(sys.argv[1])
except SystemExit as e:
    fail.append('the checked parser refuses this table -- the row floor is no '
                'longer below 98: %s' % e)
if len(rows) != 98 or len(got) != 98:
    fail.append('cmdnames[] has %d rows and names() reads %d; both must be 98 -- '
                'this phase removes no command' % (len(rows), len(got)))
for name in ('quit', 'cquit', 'registers', 'redo', 'print'):
    if name not in got:
        fail.append(':%s went, and this phase removes no row at all' % name)
if 'static_assert(sizeof(cmdnames) / sizeof(cmdnames[0]) == CMD_SIZE' not in new:
    fail.append('the static_assert on the row count went, and it is what catches '
                'an enumerator removed without its row')
if not re.search(r"^ *\{'Q', nv_error,", new, re.M):
    fail.append("the 'Q' row is no longer nv_error's, and phase 4 put it there")

# 'readonly' and 'undoreload' keep their rows: removing one is the options phase's.
for opt, var in (("'undoreload'", 'p_ur'), ("'readonly'", 'p_ro')):
    if '(char_u *)&%s,' % var not in new:
        fail.append('%s lost its option row, and that is the options phase\'s: a row '
                    'removed here would change what :set answers' % opt)

# What the sixteen cost the old file, as a difference rather than a number.
for name, want in (('check_changed', 4), ('check_changed_any', 2), ('not_exiting', 4),
                   ('bufIsChanged', 10), ('open_buffer', 5), ('buf_spname', 5),
                   ('exiting', 17), ('p_wh', 4), ('SHM_FILEINFO', 2)):
    if count(old, name) != want:
        fail.append('the input is not the file this phase was written against: '
                    '%s %d, expected %d' % (name, count(old, name), want))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s a check copied from phases 6 to 10 fails on a correct phase 11:' % '')
    print('  %-12s all five require E37 to SURVIVE and name check_changed as this' % '')
    print('  %-12s phase\'s; open_buffer goes 5 -> 4 where phases 9 and 10 pin it' % '')
    print('  %-12s at 5; and bufIsChanged goes 10 -> 7 and must not go to 0.' % '')
    sys.exit(1)
print('  %-12s the count is the assertion: 1,742 definitions -> 1,726, ELEVEN of '
      'the sixteen being the switch-buffer/switch-window island that hung off '
      "check_changed_any()'s tail and that no plan predicted" % TAG)
print('  %-12s kept: bufIsChanged 7 and curbufIsChanged 7 -- the buffer still knows '
      'it is modified, so [Modified], [+] and `:set modified?` are untouched -- '
      'text_locked 6, curbuf_locked 7 and before_quit_autocmds 2, all three still '
      'able to decline above the anchor' % '')
print('  %-12s p_wh 4 -> 2 and it is NOT write-only, which is what the obvious '
      'scan gets wrong: over every file-scope static, excluding the declaration '
      "by position, the only write-only one is vim_ignored -- upstream's sink for "
      'an ignored return value, and the same answer on the input' % '')
print('  %-12s the later phases\' line: p_ro 2 and p_ur 2 with their rows (the '
      "options phase's), read_cmd_fd 12 (the terminal's), scriptin 8, redir_fd 6 "
      "and vim_fsync 3 (the FILE* phase's)" % '')
print('  %-12s table: 98 rows untouched, names() reads 98, static_assert in place, '
      'and nv_Zet still runs `q!` for ZZ and for ZQ' % '')
PY

# --- 3. the compile, the linkage and the libc surface -------------------------------
# NOTHING IS FREED, AND THE CHECK STATES IT AS AN EQUALITY -- a `cmp` of the whole
# undefined set, so a symbol ARRIVING fails too.  Sixteen functions go and not one of
# them was libc's last caller: the refusal printed through emsg() and the island
# moved windows, neither of which reaches the C library on its own.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
if ! cmp -s "$tmp/before.u" .cache/symbols/last/undefined; then
    echo "  noquit       the libc surface moved, and this phase frees nothing:"
    echo "               gone: $(comm -23 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    echo "               came: $(comm -13 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    exit 1
fi
for keep in fclose getc putc fsync read write close dup; do
    grep -qx "$keep" .cache/symbols/last/undefined \
        || { echo "  noquit       $keep went, and it is not this phase's: fclose, getc, putc and fsync are the FILE* phase's and read, write, close and dup are the terminal's"; exit 1; }
done
for absent in open access fcntl stat getcwd strerror chmod fchmod fstat lstat unlink; do
    if grep -qx "$absent" .cache/symbols/last/undefined; then
        echo "  noquit       $absent is undefined again, and nothing here may add one"; exit 1
    fi
done
echo "  noquit       symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), the same set as a cmp -- sixteen functions go and not one was libc's last caller; fclose, getc, putc and fsync are still there and are the FILE* phase's"

# --- 4. the enumerators, before and after -------------------------------------------
# TWELVE GO AND NOTHING RENUMBERS, which is the opposite of phase 10.  typereach.py
# takes whole anonymous definitions -- the CCGD_ flags, the DOBUF_ actions, the WEE_
# flags -- and a whole definition leaving takes no survivor's value with it.  Four
# seconds a dump, taken concurrently, and it is what would catch a parallel table
# shifting under a designated one.
tools/enumvals.sh "$state/old.c" "$tmp/ev.old" &
pid_ev=$!
tools/enumvals.sh "$f" "$tmp/ev.new"
wait $pid_ev
python3 - "$tmp/ev.old" "$tmp/ev.new" <<'PY'
import sys
TAG = 'noquit'
o = dict(l.rsplit('=', 1) for l in open(sys.argv[1]).read().splitlines())
n = dict(l.rsplit('=', 1) for l in open(sys.argv[2]).read().splitlines())
gone, came = sorted(set(o) - set(n)), sorted(set(n) - set(o))
moved = sorted(k for k in set(o) & set(n) if o[k] != n[k])
WANT = ['CCGD_ALLBUF', 'CCGD_EXCMD', 'CCGD_FORCEIT', 'CCGD_MULTWIN',
        'DOBUF_GOTO', 'DOBUF_UNLOAD', 'SHM_FILEINFO',
        'WEE_CURWIN_INVALID', 'WEE_TRIGGER_ENTER_AUTOCMDS',
        'WEE_TRIGGER_LEAVE_AUTOCMDS', 'WEE_TRIGGER_NEW_AUTOCMDS', 'WEE_UNDO_SYNC']
if gone != WANT or came or moved:
    if gone != WANT:
        print('  %-12s the enumerators that went are %s, expected exactly %s'
              % (TAG, ' '.join(gone), ' '.join(WANT)))
    if came:
        print('  %-12s enumerators arrived: %s' % (TAG, ' '.join(came)))
    if moved:
        print('  %-12s survivors renumbered, and no phase that takes whole anonymous '
              'definitions may: %s' % (TAG, ' '.join(moved)))
    sys.exit(1)
print('  %-12s enumerators %d -> %d: the four CCGD_, the two DOBUF_, SHM_FILEINFO '
      'and the five WEE_ go as whole anonymous definitions, NOT ONE SURVIVOR '
      'RENUMBERED and none arrived -- the opposite of phase 10, where 85 moved'
      % (TAG, len(o), len(n)))
PY

# --- 5. the binary -------------------------------------------------------------------
# NOT tools/phasebuild.sh: it links the object the sweep compiled with this machine's
# default flags, which since zero phase 1 are not zero's (pipes/zero2-check.sh has
# the whole argument).  A full compile is the honest one.
make -C "$work" clean >/dev/null 2>&1 || true
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$bin") bytes"

# --- 6. the probes, on both binaries -------------------------------------------------
python3 - "$state/old" "$bin" <<'PY'
import concurrent.futures
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, 'tools')
import zrec
import zscreen
import zstream

TAG = 'noquit'
ESC, CR = b'\x1b', b'\r'
QUIT = ESC + b':q!' + CR
CTRL_G = b'\x07'
old_bin, new_bin = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])


def record(binary, args, keys, timeout=10):
    """tools/zstream.py's session, with the raw stream, the status and the count back.

    Everything else is that tool's and for its reasons: the binary is staged as
    `vim` because argv[0] decides what the editor is, the environment is emptied so
    that no vimrc is found, and the session is its own so that a stop signal cannot
    reach this shell.
    """
    vim = zstream.stage(binary)     # argv[0], and the copy race: tools/zstream.py
    home = tempfile.mkdtemp(prefix='zero11-home-')
    env = dict(os.environ)
    env.update(TERM='xterm', HOME=home, VIM=os.path.join(home, 'novim'),
               VIMRUNTIME=os.path.join(home, 'novim'),
               XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    d = tempfile.mkdtemp(prefix='zero11-run-')
    kf = os.path.join(d, 'keys')
    with open(kf, 'wb') as fh:
        fh.write(b''.join(keys))
    try:
        with open(kf, 'rb') as stdin:
            r = subprocess.run([vim] + list(args), stdin=stdin,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               env=env, cwd=d, timeout=timeout,
                               start_new_session=True)
        rc, out, err = r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        rc, out, err = 'timeout', b'', b''
    finally:
        shutil.rmtree(home, ignore_errors=True)
        shutil.rmtree(d, ignore_errors=True)
    scr = zscreen.Screen(24, 80)
    scr.feed(out)
    text = zrec.section('exit %s' % rc)
    text += zrec.section('bells %d' % scr.bells)
    text += zrec.section('stream %d sha=%s' % (len(out), hashlib.sha256(out).hexdigest()[:16]))
    text += zrec.section('stderr', err.decode('utf-8', 'replace').rstrip('\n'))
    for i, (dump, y, x, bells) in enumerate(scr.snaps):
        text += zrec.section('snap %d cursor=%d,%d bells=%d' % (i, y, x, bells), dump)
    return zrec.scrub(text), out.decode('utf-8', 'replace'), len(scr.snaps), rc, scr.bells


def typed(seed, *keys):
    """zcases's shape: type the seed under 'paste', then the real keys.

    IT ENDS WITH `:q!`, which is why the corpus cannot see the exit status of this
    phase: the old binary quits on that too.  `q_alone` below is the one probe that
    does not end this way.
    """
    return (['+set paste'], [b'i' + seed + ESC, b':set nopaste' + CR] + list(keys) + [QUIT])


HELLO = b'hello'

# name, (args, keys), must-differ
PROBES = [
    # --- THE PROBE: `:q` and nothing after it, where the status is the phase ---------
    ('q_alone',      (['+set paste'], [b'i' + HELLO + ESC, b':set nopaste' + CR, b':q' + CR]), True),
    # --- the declared case, and the other ways of spelling the same refusal ----------
    ('q_modified',   typed(HELLO, b':q' + CR),                          True),
    ('q_range',      typed(HELLO, b':1q' + CR),                         True),
    ('q_spell_qu',   typed(HELLO, b':qu' + CR),                         True),
    ('q_spell_quit', typed(HELLO, b':quit' + CR),                       True),
    ('q_after_undo', typed(HELLO, b'x', b':q' + CR),                    True),
    # --- everything that must not move ----------------------------------------------
    ('q_clean',      (['+set paste'], [b':set nopaste' + CR, b':q' + CR]), False),
    ('q_bang',       (['+set paste'], [b'i' + HELLO + ESC, b':set nopaste' + CR, b':q!' + CR]), False),
    ('zz_key',       typed(HELLO, b'ZZ'),                               False),
    ('zq_key',       typed(HELLO, b'ZQ'),                               False),
    ('cquit',        (['+set paste'], [b'i' + HELLO + ESC, b':set nopaste' + CR, b':cq' + CR]), False),
    ('ctrl_g',       typed(b'a' + CR + b'b', CTRL_G),                   False),
    ('cmd_set_ro',   typed(HELLO, b':set ro?' + CR),                    False),
    ('cmd_set_mod',  typed(HELLO, b':set modified?' + CR),              False),
    ('reg_list',     typed(HELLO, b'yy', b':registers' + CR),           False),
    ('cmd_undo',     typed(b'alpha', b'x', b'u'),                       False),
    ('editing',      typed(b'alpha' + CR + b'beta', b'0dwA-tail' + ESC, b'u', b'yyp'), False),
]


def one(probe):
    name, (args, keys), differ = probe
    return (name, record(old_bin, args, keys), record(new_bin, args, keys), differ)


with concurrent.futures.ThreadPoolExecutor(max_workers=len(PROBES)) as ex:
    results = list(ex.map(one, PROBES))

fail, moved, static = [], [], []
for name, o, n, differ in results:
    same = o[0] == n[0]
    if differ and same:
        fail.append('%s was to move and did not' % name)
    if not differ and not same:
        fail.append('%s moved and was not to' % name)
    (static if same else moved).append(name)

by = {name: (o, n) for name, o, n, _ in results}
E37 = 'E37: No write since last change (add ! to override)'

# THE PROBE.  `:q` with NOTHING after it: the old binary draws E37, runs out of
# stdin, prints `Vim: Finished.` and exits 1; this one quits and exits 0.  That
# status is the whole phase measured from outside and the corpus cannot see it,
# because every zcases.py case ends with a trailing `:q!`.
(o, ostream, _, orc, obells), (n, nstream, _, nrc, nbells) = by['q_alone']
if E37 not in o:
    fail.append('q_alone: the input binary did not refuse, so this proves nothing '
                'about a refusal being removed')
if orc != 1:
    fail.append('q_alone: the input binary exited %r, expected 1 -- it draws E37, '
                'runs out of stdin and gives up' % orc)
if 'Vim: Finished.' not in ostream and 'Vim: Finished.' not in o:
    fail.append('q_alone: the input binary did not print `Vim: Finished.`, so it did '
                'not reach end of input after refusing')
if E37 in n:
    fail.append('q_alone: this binary still refuses')
if nrc != 0:
    fail.append('q_alone: this binary exited %r, expected 0 -- `:q` quits now' % nrc)

# The declared case, and the four other spellings of the same refusal.  Each must
# have refused BEFORE and must not now.
for name in ('q_modified', 'q_range', 'q_spell_qu', 'q_spell_quit', 'q_after_undo'):
    (o, _, osn, _, obells), (n, _, nsn, _, nbells) = by[name]
    if E37 not in o:
        fail.append('%s: the input binary did not refuse, so "it moved" is not '
                    'evidence of anything' % name)
    if E37 in n:
        fail.append('%s: this binary still refuses' % name)
    if nsn >= osn:
        fail.append('%s: the record did not lose a snapshot (%d -> %d), and the E37 '
                    'screen is what it loses' % (name, osn, nsn))
(o, _, osn, _, obells), (n, _, nsn, _, nbells) = by['q_modified']
if (obells, nbells) != (1, 0):
    fail.append('q_modified: the bells went %d -> %d, expected 1 -> 0 -- the refusal '
                'beeped and nothing here does' % (obells, nbells))

# The ones that must not move are required to be DOING something, not failing alike.
(o, _, _, orc, _), (n, _, _, nrc, _) = by['q_clean']
if E37 in o or E37 in n or (orc, nrc) != (0, 0):
    fail.append('q_clean: `:q` on an UNMODIFIED buffer must quit with status 0 on '
                'both binaries and refuse on neither -- it took the else arm before '
                'this phase and takes it now, which is what makes it the pair of '
                'q_alone (%r, %r)' % (orc, nrc))
(o, _, _, orc, _), (n, _, _, nrc, _) = by['cquit']
if (orc, nrc) != (1, 1):
    fail.append('cquit: `:cq` exits 1 on both binaries and this phase does not touch '
                'it (%r, %r)' % (orc, nrc))
(o, _, _, _, _), (n, _, _, _, _) = by['ctrl_g']
if '[Modified]' not in n:
    fail.append('ctrl_g: CTRL-G no longer says [Modified], and the state is exactly '
                'what this phase does NOT remove')
(o, _, _, _, _), (n, ns, _, _, _) = by['cmd_set_mod']
if 'modified' not in ns:
    fail.append('cmd_set_mod: `:set modified?` answered nothing, so "it did not '
                'move" is two failures agreeing')
for name, want in (('editing', 'alpha'), ('reg_list', 'hello'), ('cmd_undo', 'alpha')):
    (o, _, _, _, _), (n, ns, _, _, _) = by[name]
    if want not in n and want not in ns:
        fail.append('%s: the new binary no longer shows %r, so "it did not move" is '
                    'two failures agreeing' % (name, want))
# ZZ and ZQ have run `q!` since phase 6 and are the same thing as each other.
(zz, _, _, _, _), _ = by['zz_key']
(zq, _, _, _, _), _ = by['zq_key']
if zz != zq:
    fail.append('ZZ and ZQ do not leave the same record, and they have run the same '
                'command string since phase 6')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s the corpus sees ONE case and cannot tell "the refusal was' % '')
    print('  %-12s removed" from "a message changed": every zcases.py case ends' % '')
    print('  %-12s with a trailing `:q!`, which quits the old binary too, so the' % '')
    print('  %-12s exit status is 0 either side there.  q_alone is the probe.' % '')
    sys.exit(1)
print('  %-12s probes: %d moved (%s), %d unchanged' % (TAG, len(moved), ' '.join(moved), len(static)))
print('  %-12s q_alone is the phase: `:q` with nothing after it draws E37, runs out '
      'of stdin, prints `Vim: Finished.` and exits 1 on the binary this phase was '
      'handed, and quits with status 0 here -- which no recording can see' % '')
print('  %-12s and what did not move is doing its work: `:q` on an unmodified '
      'buffer (0 either side), `:q!`, ZZ and ZQ identical to each other, `:cq` '
      'exiting 1, CTRL-G still saying [Modified], `:set modified?`, :registers and '
      'an ordinary editing session' % '')
PY

# --- 7. a real terminal ---------------------------------------------------------------
# Every probe above went through a pipe.  On a pty the old binary answers E37 to `:q`
# and stays, so the `:q!` after it is what ends the session; this one is gone on the
# `:q` and the `:q!` reaches nothing.  An ordinary editing session beside it must be
# identical either side.
python3 - "$state/old" "$bin" <<'PY'
import os, re, sys, tempfile
sys.path.insert(0, 'tools')
import ptyrun
TAG = 'noquit'
home = tempfile.mkdtemp(prefix='zero11-home-')
env = dict(os.environ, HOME=home, VIM=os.path.join(home, 'novim'),
           VIMRUNTIME=os.path.join(home, 'novim'),
           XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
for k in ('VIMINIT', 'EXINIT', 'MYVIMRC'):
    env.pop(k, None)


def session(binary, keys):
    d = tempfile.mkdtemp(prefix='zero11-pty-')
    text, status = ptyrun.session(binary, [], keys, term='xterm', cwd=d,
                                  settle=0.6, env=env)
    return text.decode('utf-8', 'replace'), status


QUIT = [b'ityped on a terminal\x1b', b':q\r', b':q!\r']
EDIT = [b'ialpha\rbeta\x1b', b'ggdwA-tail\x1b', b'u', b':q!\r']
fail = []
o, ostat = session(sys.argv[1], QUIT)
n, nstat = session(sys.argv[2], QUIT)
if 'E37: No write since last change' not in o:
    fail.append('the pty session did not refuse on the input binary, so it proves '
                'nothing')
if 'E37' in n:
    fail.append('the pty session still refuses on the new binary')
if ':q!' not in o:
    fail.append('the `:q!` did not reach the input binary, so the `:q` there did '
                'not leave the editor running -- which is the evidence that it '
                'refused rather than quitting')
# THE OTHER DIRECTION IS NOT ASSERTED, AND THAT IS DELIBERATE.  "the `:q!` did not
# reach the new binary" looks like the obvious pair and is a race: once the editor
# has quit the pty leaves raw mode, so whether the trailing keystrokes are echoed
# back depends on how fast the process exits.  Measured: it passes alone and fails
# under `make zero-verify`, which runs fourteen phases at once.  What the `:q` quit
# is `q_alone`'s to say, through a pipe and by its exit status, where nothing is
# timing-dependent; this section's claim is that the refusal is gone on a REAL
# TERMINAL, and E37 is the whole of that.
eo, eos = session(sys.argv[1], EDIT)
en, ens = session(sys.argv[2], EDIT)
# THE EDITING SESSION IS COMPARED WHOLE, WITH ONE FIELD BLINDED, AND THE FIELD IS A
# WALL CLOCK.  The `u` prints `1 change; before #3  N second(s) ago`, where N is how
# long ago the change was made -- a reading of the clock, which neither binary
# decides.  ptyrun writes the keystrokes 0.6 s apart, so the elapsed time from the
# `A-tail` ESC to the `u` sits ON the one-second boundary, and which side of it the
# two sessions fall is how busy the machine is.  That, and nothing else, is what
# failed `make zero-pass` here on a tree whose r11 `make zero-verify` had reproduced
# minutes earlier.  MEASURED, on the two binaries this check is handed, under a load
# that crosses the boundary and comes back: 30 of 240 runs of this section failed
# (12.5 %), every one of them with the message below and differing in that field
# ALONE -- 480 sessions produced exactly two texts, `0 seconds ago` and `1 second
# ago` -- and 0 of 120 failed with the field blinded.  Everything else in the stream,
# `1 change; before #3` included, is still compared byte for byte, and the guard
# below is what stops the blinding from quietly becoming a blinding of nothing.
AGO = re.compile(r'\d+ seconds? ago')
if 'change; before #' not in eo or not AGO.search(eo):
    fail.append('the undo report with its `N seconds ago` is not in the pty session '
                'on the input binary, so blinding the clock blinds nothing and the '
                'comparison below is not the one described: %r' % eo[-200:])
if AGO.sub('<ago>', eo) != AGO.sub('<ago>', en) or eos != ens:
    fail.append('an ordinary pty editing session moved, and nothing here may move it')
if 'alpha' not in en:
    fail.append('the pty editing session did nothing, so "identical" is two '
                'failures agreeing')
if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s a real terminal: `:q` draws E37 and leaves the editor running on the '
      'binary this phase was handed, so its `:q!` is what ends the session, and here '
      'there is no E37 at all -- an ordinary editing session is identical either '
      'side' % TAG)
PY
