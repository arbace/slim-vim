#!/bin/sh
# Zero phase 4, the check -- Ex mode, silent mode and the four options are gone.
# See pipes/zero4-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero4-check.sh <work-dir> <state-dir>     (run from the repository root)
#
# Runs after pipes/zero4-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# built from the boundary's own makefile flags.
#
# THE DECLARED DELTA IS NOT THE WHOLE EVIDENCE HERE, for two reasons that pull in
# opposite directions.  `pipes/zero.delta` says six records move -- `key_Q`,
# `key_gQ` and the argv rows `-e`, `-E`, `-e -s`, `-v` -- and tools/zerodelta.sh
# proves that exactly those and nothing else did, against baselines recorded from
# whim-vim.  What it cannot show is a BEFORE: the baselines are one recording of one
# binary, so "the old one entered Ex mode and the new one beeps" is not a sentence
# it can say.  The probes below say it, by running both binaries.
#
# They are in two halves and both halves are the point:
#
#   MUST DIFFER   the six records above and a pty session, each required to show Ex
#                 mode on the OLD binary.  A probe that only checks the new binary
#                 passes just as well on a phase that did nothing.
#   MUST NOT      `-s` alone (already an unknown option before this phase, so it is
#                 not in the delta), every `+{command}` form, `:append`/`:insert`/
#                 `:change` (which read through getexline, not the Ex-mode reader),
#                 `:visual`/`:view`/`:vi`/`:ex` from Normal mode (whose Ex-mode
#                 escape this phase folded away), bare `-`, `--`, one and two file
#                 arguments, the three `-T` spellings, a plain edit and an editing
#                 pty session.
#
# A record is built the way `zcases` builds one and scrubbed the same way
# (tools/zrec.py): `mainerr()` prints the version banner, which carries __DATE__ and
# __TIME__, so two binaries built a minute apart disagree on stderr for a reason
# that is not the editor's behaviour -- which is exactly why `-s` reads as unchanged
# and must.
set -eu

work=${1:?usage: zero4-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero4-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 1. what the cut removed -------------------------------------------------------
# The 21 identifiers the edit counted, every one of them now at zero, and the two
# strings that were only reachable through them.  `e_at_end_of_file`'s string is here
# and not in the edit because the variable outlives the edit by one sweep.
for gone in exmode_active silent_mode pending_exmode_active exmode_plus exmode_was \
            do_exmode getexmodeline nv_exmode EXMODE_NORMAL EXMODE_VIM BO_EX \
            ex_pressedreturn ex_no_reprint ex_exitval previous_got_int use_plus_cmd \
            s_vbuf e_at_end_of_file noexmode check_tty mch_input_isatty; do
    n=$(grep -cw -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  noexmode     '$gone' still has $n mentions"; exit 1; }
done
for gone in 'Entering Ex mode' 'E501: At end-of-file'; do
    n=$(grep -cF -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  noexmode     '$gone' still has $n mentions"; exit 1; }
done
# By word, not by substring: `stdout_isatty` is phase 2's and survives this phase,
# and it contains `stdout`.
for gone in setvbuf stdout; do
    n=$(grep -cw -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  noexmode     '$gone' still has $n mentions"; exit 1; }
done
# COUNTED IN OCCURRENCES, NOT LINES (pipes/zero2-check.sh says why): `!isatty(fd) &&
# isatty(read_cmd_fd)` puts two calls on one line, and `grep -c` counts the line once.
occurrences() {
    grep -oE -- "$1" "$2" | grep -c '' || true
}
n=$(occurrences '\bisatty\(' "$f")
[ "$n" = 4 ] || { echo "  noexmode     isatty is called $n times, expected 4: mch_input_isatty's went with check_tty"; exit 1; }
echo "  noexmode     0 mentions of all 21, neither Ex-mode string, isatty down to 4 calls"

# --- 2. what it deliberately kept ---------------------------------------------------
# A row is repointed, never deleted: a hole in nv_cmds[] moves every key past it
# (`nvidx`, run by phasecheck.sh below, is the other half of this).
grep -q "^     {'Q', nv_error, NV_NCW, 0} ,$" "$f" \
    || { echo "  noexmode     the 'Q' row is not a repointed nv_error row"; exit 1; }
grep -q '^getexline(' "$f" \
    || { echo "  noexmode     getexline went -- :append, :insert and :change read through it"; exit 1; }
grep -q '^exe_commands(' "$f" \
    || { echo "  noexmode     exe_commands went, and with it every +{command}"; exit 1; }
# The argv phase's, named one by one so that this phase cutting into it fails here.
for kept in 'EDIT_STDIN' 'read_cmd_fd = 2;' 'had_minmin' 'buflist_add' \
            'ME_TOO_MANY_ARGS' "case 'T':" 'want_full_screen'; do
    grep -qF -- "$kept" "$f" \
        || { echo "  noexmode     '$kept' went, and it is the argv phase's to take"; exit 1; }
done
echo "  noexmode     kept: the 'Q' row at nv_error, getexline, exe_commands, and everything argv owns"

# --- 3. the compile, the linkage and the libc surface ------------------------------
# The symbol list the stage started with, before phasecheck.sh consumes it: what
# this phase must give back is setvbuf and stdout, and NOT isatty, which still has
# four callers.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
gone=$(comm -23 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')
[ "$gone" = "setvbuf stdout " ] \
    || { echo "  noexmode     the libc surface lost '$gone', expected exactly 'setvbuf stdout '"; exit 1; }
grep -qx isatty .cache/symbols/last/undefined \
    || { echo "  noexmode     isatty left the binary -- four calls still name it"; exit 1; }
echo "  noexmode     symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), gone: setvbuf stdout; isatty stays"

# --- 4. the binary -----------------------------------------------------------------
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

# --- 5. the probes, both halves ----------------------------------------------------
python3 - "$state/old" "$bin" <<'PY'
import concurrent.futures
import hashlib
import os
import sys

sys.path.insert(0, 'tools')
import zrec
import zstream

TAG = 'noexmode'
ESC, CR = b'\x1b', b'\r'
QUIT = ESC + b':q!' + CR
old_bin, new_bin = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])


def typed(seed, *keys):
    """zcases's shape: type the seed under 'paste', then the real keys."""
    args = ['+set paste']
    return args, [b'i' + seed + ESC, b':set nopaste' + CR] + list(keys) + [QUIT]


def keys_only(*keys):
    return [], list(keys) + [QUIT]


ALPHA = b'alpha' + CR + b'beta'

# name, (args, keys), must-differ
PROBES = [
    # --- the six the delta declares, each required to show Ex mode on the old
    #     binary: a probe the input passes is a probe that proves nothing.
    ('key_Q',        typed(ALPHA, b'Q'),                       True),
    ('key_gQ',       typed(ALPHA, b'gQ'),                      True),
    ('argv_e',       (['-e'], [QUIT]),                         True),
    ('argv_E',       (['-E'], [QUIT]),                         True),
    ('argv_e_s',     (['-e', '-s'], [QUIT]),                   True),
    ('argv_v',       (['-v'], [QUIT]),                         True),
    # --- and everything that must not move -------------------------------------
    # `-s` alone was never an option: case 's' set silent mode only when Ex mode
    # was already on and called mainerr() otherwise.  It is not in the delta.
    ('argv_s',       (['-s'], [QUIT]),                         False),
    ('argv_none',    ([], [QUIT]),                             False),
    ('argv_plus',    (['+'], [QUIT]),                          False),
    ('argv_plus_q',  (['+q!'], [QUIT]),                        False),
    ('argv_plus_set', (['+set nu', '+q!'], [QUIT]),            False),
    ('argv_plus_nu', (['+set nu'], [QUIT]),                    False),
    ('argv_plus_file', (['+q!', 'f.txt'], [QUIT]),             False),
    ('argv_minus',   (['-'], [QUIT]),                          False),
    ('argv_minmin',  (['--'], [QUIT]),                         False),
    ('argv_minmin_plus', (['--', '+q!'], [QUIT]),              False),
    ('argv_file',    (['f.txt'], [QUIT]),                      False),
    ('argv_files',   (['f.txt', 'g.txt'], [QUIT]),             False),
    ('argv_T',       (['-T'], [QUIT]),                         False),
    ('argv_T_xterm', (['-T', 'xterm'], [QUIT]),                False),
    ('argv_Txterm',  (['-Txterm'], [QUIT]),                    False),
    # getexline, not getexmodeline: the three commands that read their own lines.
    ('ex_append',    keys_only(b':append' + CR + b'one' + CR + b'two' + CR + b'.' + CR), False),
    ('ex_insert',    keys_only(b':insert' + CR + b'first' + CR + b'.' + CR),  False),
    ('ex_change',    typed(ALPHA, b':change' + CR + b'other' + CR + b'.' + CR), False),
    # The commands whose Ex-mode escape this phase folded away, from Normal mode,
    # where they never entered it.
    ('cmd_visual',   typed(ALPHA, b':visual' + CR),            False),
    ('cmd_vi',       typed(ALPHA, b':vi' + CR),                False),
    ('cmd_view',     typed(ALPHA, b':view' + CR),              False),
    ('cmd_ex',       typed(ALPHA, b':ex' + CR),                False),
    # And an ordinary edit, which is the whole point of keeping the rest.
    ('editing',      typed(ALPHA, b'0dwA-tail' + ESC, b'u', b'\x12', b'yyp'), False),
]


def record(binary, args, keys):
    try:
        scr, out, err, rc = zstream.session(binary, keys, args=args, timeout=8)
    except zstream.Blocked:
        # `vim -` reads the keystroke file as buffer text and then waits for keys
        # that never come.  That is a recording, not a crash (`zargv`).
        return zrec.section('blocked', 'took the input over and never returned'), b'', 0
    text = zrec.section('exit %s' % rc)
    text += zrec.section('bells %d' % scr.bells)
    text += zrec.section('stream %d sha=%s' % (len(out), hashlib.sha256(out).hexdigest()[:16]))
    text += zrec.section('stderr', err.decode('utf-8', 'replace').rstrip('\n'))
    for i, (dump, y, x, bells) in enumerate(scr.snaps):
        text += zrec.section('snap %d cursor=%d,%d bells=%d' % (i, y, x, bells), dump)
    return zrec.scrub(text), out, scr.bells


def one(probe):
    name, (args, keys), differ = probe
    o = record(old_bin, args, keys)
    n = record(new_bin, args, keys)
    return name, o, n, differ


fail = []
with concurrent.futures.ThreadPoolExecutor(max_workers=len(PROBES)) as ex:
    results = list(ex.map(one, PROBES))

moved, static = [], []
for name, o, n, differ in results:
    same = o[0] == n[0]
    if differ and same:
        fail.append('%s was to move and did not' % name)
    if not differ and not same:
        fail.append('%s moved and was not to' % name)
    (static if same else moved).append(name)

# The six that moved must have moved for the stated reason, and the reason has to
# be visible on the OLD binary: Ex mode in the stream for the two keys, and an
# option the old parser accepted for the four command lines.
by = {name: (o, n) for name, o, n, _ in results}
for name in ('key_Q', 'key_gQ'):
    o, n = by[name]
    if b'Entering Ex mode' not in o[1]:
        fail.append('%s: the input binary did not enter Ex mode, so this proves nothing' % name)
    if b'Entering Ex mode' in n[1]:
        fail.append('%s: the new binary still enters Ex mode' % name)
    if n[2] <= o[2]:
        fail.append('%s: the key does not beep now (%d bells, was %d)' % (name, n[2], o[2]))
for name in ('argv_e', 'argv_E', 'argv_e_s', 'argv_v'):
    o, n = by[name]
    if 'Unknown option argument' in o[0]:
        fail.append('%s: the input binary already rejected it, so this proves nothing' % name)
    if 'Unknown option argument' not in n[0]:
        fail.append('%s: it is not an unknown option now' % name)
o, n = by['argv_s']
if 'Unknown option argument' not in o[0] or 'Unknown option argument' not in n[0]:
    fail.append('argv_s: -s was to be an unknown option on both binaries')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s a probe that cannot fail is not evidence, and one that fails' % '')
    print('  %-12s differently is not this probe.' % '')
    sys.exit(1)
print('  %-12s probes: %d moved (%s), %d unchanged' % (TAG, len(moved), ' '.join(moved), len(static)))
PY

# --- 6. a real terminal, where none of this went through a pipe --------------------
# tools/zpty.py drives four of these in the declared delta and none of them presses
# Q; this is the before-and-after the delta cannot give, because it has no old
# binary.  Two sessions: the one that entered Ex mode, and an ordinary edit.
python3 - "$state/old" "$bin" <<'PY'
import os, sys, tempfile
sys.path.insert(0, 'tools')
import ptyrun
TAG = 'noexmode'
ESC = b'\x1b'
home = tempfile.mkdtemp(prefix='zero4-home-')
env = dict(os.environ, HOME=home, VIM=os.path.join(home, 'novim'),
           VIMRUNTIME=os.path.join(home, 'novim'),
           XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
for k in ('VIMINIT', 'EXINIT', 'MYVIMRC'):
    env.pop(k, None)


def session(binary, keys):
    d = tempfile.mkdtemp(prefix='zero4-pty-')
    text, status = ptyrun.session(binary, [], keys, term='xterm', cwd=d,
                                  settle=0.6, env=env)
    return text.decode('utf-8', 'replace'), status


# Q, then the word that leaves Ex mode, then quit.  On the old binary the first key
# prints the banner and `visual` is the way out; on the new one Q beeps and the same
# six letters are Normal-mode keys -- `v` starts Visual, `a` ends up in Insert -- so
# the ESC is not decoration: without it `:q!` is typed into the buffer and the
# session runs to the timeout and is killed (status 9, measured).
ex = [session(b, [b'ialpha\x1b', b'Q', b'visual\r', b'\x1b:q!\r'])
      for b in (sys.argv[1], sys.argv[2])]
if 'Entering Ex mode' not in ex[0][0]:
    sys.exit('  %-12s the input binary did not enter Ex mode on a pty -- this proves nothing' % TAG)
if 'Entering Ex mode' in ex[1][0]:
    sys.exit('  %-12s the new binary still enters Ex mode on a pty' % TAG)
for name, r in (('old', ex[0]), ('new', ex[1])):
    if r[1] != 0:
        sys.exit('  %-12s the Ex-mode pty session exited %s on the %s binary' % (TAG, r[1], name))

# And an ordinary editing session, which must be the same on both.
edit = [session(b, [b'ityped here\x1b', b'0dw', b':set ruler?\r', b':q!\r'])
        for b in (sys.argv[1], sys.argv[2])]
if 'here' not in edit[0][0] or 'ruler' not in edit[0][0]:
    sys.exit('  %-12s the editing pty session did not edit on the input binary' % TAG)
if edit[0] != edit[1]:
    sys.exit('  %-12s the editing pty session moved: %r -> %r'
             % (TAG, edit[0][1], edit[1][1]))
print('  %-12s pty: Ex mode entered by the old binary and by nothing now; '
      'the editing session identical either side' % TAG)
PY
