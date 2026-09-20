#!/bin/sh
# Zero phase 5, the check -- argv is `+{command}` and `-T {term}`, and nothing else.
# See pipes/zero5-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero5-check.sh <work-dir> <state-dir>     (run from the repository root)
#
# Runs after pipes/zero5-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `enums-before`, that binary's DWARF enumerator values.
#
# FOUR THINGS ARE PROVED HERE, and only the first is a grep.
#
# 1. THE CUT.  Six identifiers at zero mentions, the two strings that went with
#    them, and -- against the phases that come after -- `read_stdin`'s 23 remaining
#    mentions, every one of them the PARAMETER that the "nothing reads a byte"
#    phase owns, and `read_cmd_fd`'s twelve, which the same phase owns.  A phase
#    that reached past its own boundary would fail here rather than quietly widen.
#
# 2. THE RENUMBERING.  `main_errors[]` is indexed by the ME_* enumerators, so
#    removing ME_TOO_MANY_ARGS moves the three after it.  That is exactly what
#    CLAUDE.md says a build is perfectly happy to do wrongly, so it is checked
#    against DWARF and not against the build: every enumerator in the binary this
#    phase was handed must be in the one it made with the same value, except
#    ME_TOO_MANY_ARGS and the three EDIT_*, which must be gone, and ME_ARG_MISSING,
#    ME_GARBAGE and ME_EXTRA_CMD, which must each be exactly one lower.  There are
#    1,327 of them and a wrong table index would not show up anywhere else.
#
# 3. THE PROBES, in two halves, run on BOTH binaries.  The declared delta
#    (tools/zerodelta.sh) says exactly six of the 30 command lines moved and
#    nothing else did, against baselines recorded from whim-vim -- but the
#    baselines are one recording of one binary, so they cannot say "the old one
#    opened the file".  These say it:
#
#      MUST DIFFER   a file argument, two file arguments, a bare `-` with text on
#                    stdin, `--`, `-- +q!` and `+q! f.txt`, each also required to
#                    show the OLD behaviour on the OLD binary -- a probe that only
#                    looks at the new binary passes on a phase that did nothing.
#      MUST NOT      every `+{command}` form including `+set paste`, the three `-T`
#                    spellings and an unknown terminal name, the options that were
#                    already unknown, an ordinary keystroke edit, and a pty session.
#
# 4. THE INSTRUMENT SWAP, which this phase is the cause of.  tools/termcheck.py is
#    whim's, and it asks its question with a file argument.  From this boundary on
#    that is an unknown option and all nineteen of its rows read `(none)` -- so
#    zero's recording now uses `ztermcheck`, which is termcheck.py with its
#    ask() replaced and nothing else.  Both halves are measured here: the new tool
#    records the baseline's nineteen rows byte for byte from the binary this phase
#    was handed, and the old tool records nothing but `(none)` from the one it made.
#
# A record is built the way `zcases` builds one and scrubbed the same way
# (tools/zrec.py): mainerr() prints the version banner, which carries __DATE__ and
# __TIME__, so two binaries built a minute apart disagree on stderr for a reason
# that is not the editor's behaviour.
set -eu

work=${1:?usage: zero5-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero5-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 1. what the cut removed -------------------------------------------------------
for gone in had_minmin edit_type EDIT_NONE EDIT_FILE EDIT_STDIN ME_TOO_MANY_ARGS \
            buflist_add; do
    n=$(grep -cw -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  noargv       '$gone' still has $n mentions"; exit 1; }
done
for gone in 'Too many edit arguments' 'read_stdin(void)' 'read_stdin();'; do
    n=$(grep -cF -- "$gone" "$f" || true)
    [ "$n" = 0 ] || { echo "  noargv       '$gone' still has $n mentions"; exit 1; }
done
# AND WHAT IT DID NOT TOUCH.  `read_stdin` as a parameter, and `read_cmd_fd`, are
# the stdin phase's (ZERO-PLAN.md P8): the function went and the arms that read a
# byte did not.  Counted, so that taking them here would fail here.
n=$(grep -ow 'read_stdin' "$f" | grep -c '' || true)
[ "$n" = 23 ] || { echo "  noargv       read_stdin has $n mentions, expected the 23 that are the parameter the stdin phase owns"; exit 1; }
n=$(grep -ow 'read_cmd_fd' "$f" | grep -c '' || true)
[ "$n" = 12 ] || { echo "  noargv       read_cmd_fd has $n mentions, expected 12: the assignment was argv's, the readers are not"; exit 1; }
echo "  noargv       0 mentions of all seven; read_stdin's 23 parameter mentions and read_cmd_fd's 12 readers untouched"

# --- 2. what it deliberately kept ---------------------------------------------------
for kept in 'MAX_ARG_CMDS' 'ME_EXTRA_CMD' 'ME_GARBAGE' 'ME_UNKNOWN_OPTION' \
            'ME_ARG_MISSING' 'mainerr_arg_missing' 'want_argument' "case 'T':" \
            "if (argv[0][0] == '+')" 'p_paste'; do
    grep -qF -- "$kept" "$f" \
        || { echo "  noargv       '$kept' went, and argv ends as +{command} and -T {term}"; exit 1; }
done
grep -q '^exe_commands(' "$f" \
    || { echo "  noargv       exe_commands went, and with it every +{command}"; exit 1; }
# The ME_* enumerators are main_errors[]'s indices: 0..3, in the table's order.
python3 - "$f" <<'PY'
import re, sys
t = open(sys.argv[1], errors='surrogateescape').read()
pairs = re.findall(r'^enum \{ (ME_\w+) = (\d+) \};$', t, re.M)
want = [('ME_UNKNOWN_OPTION', '0'), ('ME_ARG_MISSING', '1'),
        ('ME_GARBAGE', '2'), ('ME_EXTRA_CMD', '3')]
if pairs != want:
    sys.exit('  %-12s the ME_* enumerators are %r, expected %r' % ('noargv', pairs, want))
rows = re.search(r'^static char \*\(main_errors\[\]\) =\n\{\n(.*?)^\};\n', t, re.M | re.S)
if not rows or len(rows.group(1).splitlines()) != 5:
    sys.exit('  %-12s main_errors[] has %s rows, expected 5: four the enumerators index '
             'and the one whim left unreachable'
             % ('noargv', len(rows.group(1).splitlines()) if rows else 'no'))
if 'Too many edit arguments' in rows.group(1):
    sys.exit('  %-12s main_errors[] still carries the ME_TOO_MANY_ARGS row' % 'noargv')
PY
echo "  noargv       kept: +{command} with MAX_ARG_CMDS, -T with want_argument, ME_UNKNOWN_OPTION for the rest, exe_commands, 'paste'"

# --- 3. the compile, the linkage and the libc surface ------------------------------
# NOTHING IS FREED HERE, and that is the measurement rather than a disappointment:
# read_stdin()'s close() and dup() have other callers, and buflist_add() calls
# nothing of libc's directly.  Stated as an equality so that a symbol arriving --
# which a fold can do -- fails.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
if ! cmp -s "$tmp/before.u" .cache/symbols/last/undefined; then
    echo "  noargv       the libc surface moved, and this phase frees nothing:"
    diff "$tmp/before.u" .cache/symbols/last/undefined | sed 's/^/               /'
    exit 1
fi
echo "  noargv       symbols $(cat .cache/symbols/last/after), the same set: nothing this cut removed was libc's last caller"

# --- 4. the enumerators, from DWARF --------------------------------------------------
tools/enumvals.sh "$f" "$tmp/enums-after"
python3 - "$state/enums-before" "$tmp/enums-after" <<'PY'
import sys
TAG = 'noargv'


def load(p):
    return dict(l.rstrip('\n').split('=', 1) for l in open(p) if '=' in l)


before, after = load(sys.argv[1]), load(sys.argv[2])
GONE = {'ME_TOO_MANY_ARGS', 'EDIT_NONE', 'EDIT_FILE', 'EDIT_STDIN'}
MOVED = {'ME_ARG_MISSING': ('2', '1'), 'ME_GARBAGE': ('3', '2'), 'ME_EXTRA_CMD': ('4', '3')}
fail = []
for n in sorted(GONE):
    if n not in before:
        fail.append('%s was not in the input binary at all, so its removal proves nothing' % n)
    if n in after:
        fail.append('%s survives with value %s' % (n, after[n]))
for n, (was, now) in sorted(MOVED.items()):
    if before.get(n) != was or after.get(n) != now:
        fail.append('%s is %s -> %s, expected %s -> %s'
                    % (n, before.get(n), after.get(n), was, now))
still = [n for n in before if n not in GONE and n not in MOVED]
moved = [n for n in still if n in after and after[n] != before[n]]
if moved:
    fail.append('%d enumerators renumbered and were not to: %s'
                % (len(moved), ' '.join(sorted(moved)[:8])))
lost = [n for n in still if n not in after]
if lost:
    fail.append('%d enumerators left the binary and were not to: %s'
                % (len(lost), ' '.join(sorted(lost)[:8])))
if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s main_errors[] is indexed by these, and the build cannot see a' % '')
    print('  %-12s wrong index.  DWARF can.' % '')
    sys.exit(1)
print('  %-12s enumerators: %d in, %d out; 4 gone, 3 renumbered by one, %d unmoved'
      % (TAG, len(before), len(after), len(still) - len(moved)))
PY

# --- 5. the binary -----------------------------------------------------------------
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

# --- 6. the probes, both halves ----------------------------------------------------
python3 - "$state/old" "$bin" <<'PY'
import concurrent.futures
import hashlib
import os
import sys

sys.path.insert(0, 'tools')
import zrec
import zstream

TAG = 'noargv'
ESC, CR = b'\x1b', b'\r'
QUIT = ESC + b':q!' + CR
old_bin, new_bin = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])


def typed(seed, *keys):
    """zcases's shape: type the seed under 'paste', then the real keys."""
    args = ['+set paste']
    return args, [b'i' + seed + ESC, b':set nopaste' + CR] + list(keys) + [QUIT]


ALPHA = b'alpha' + CR + b'beta'

# name, (args, keys), must-differ
PROBES = [
    # --- the six the delta declares.  Each is a way of naming a FILE or a STREAM
    #     to edit, and each is required to do that on the OLD binary.
    ('argv_file',      (['f.txt'], [QUIT]),                    True),
    ('argv_files',     (['f.txt', 'g.txt'], [QUIT]),           True),
    # A bare `-` read the keystroke file itself as the buffer, closed fd 0 and
    # waited on fd 2 for keys that never came: the old record is `blocked`.
    ('argv_minus',     (['-'], [b'text on stdin' + CR, QUIT]), True),
    ('argv_minmin',    (['--'], [QUIT]),                       True),
    ('argv_minmin_plus', (['--', '+q!'], [QUIT]),              True),
    ('argv_plus_file', (['+q!', 'f.txt'], [QUIT]),             True),
    # --- and everything that must not move -------------------------------------
    ('argv_none',      ([], [QUIT]),                           False),
    ('argv_plus',      (['+'], [QUIT]),                        False),
    ('argv_plus_q',    (['+q!'], [QUIT]),                      False),
    ('argv_plus_nu',   (['+set nu'], [QUIT]),                  False),
    ('argv_plus_two',  (['+set nu', '+q!'], [QUIT]),           False),
    # `'paste'` is what every case of the corpus seeds itself under, and it goes in
    # as a `+{command}`: this phase is where both could have been lost together.
    ('argv_plus_paste', (['+set paste'], [b'ihello' + ESC, QUIT]), False),
    ('argv_T_xterm',   (['-T', 'xterm'], [QUIT]),              False),
    ('argv_T',         (['-T'], [QUIT]),                       False),
    ('argv_Txterm',    (['-Txterm'], [QUIT]),                  False),
    ('argv_T_unknown', (['-T', 'no-such-term-9x'], [QUIT]),    False),
    # Already unknown before this phase, and unknown in the same words after it.
    ('argv_R',         (['-R'], [QUIT]),                       False),
    ('argv_e',         (['-e'], [QUIT]),                       False),
    ('argv_help',      (['--help'], [QUIT]),                   False),
    ('argv_version',   (['--version'], [QUIT]),                False),
    ('argv_ttyfail',   (['--ttyfail'], [QUIT]),                False),
    # And an ordinary edit, which is the whole point of keeping the rest.
    ('editing',        typed(ALPHA, b'0dwA-tail' + ESC, b'u', b'\x12', b'yyp'), False),
]


def record(binary, args, keys):
    try:
        scr, out, err, rc = zstream.session(binary, keys, args=args, timeout=8)
    except zstream.Blocked:
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

by = {name: (o, n) for name, o, n, _ in results}
UNKNOWN = 'Unknown option argument'
# Each of the six must have moved FOR ITS OWN REASON, visible on the old binary.
for name in ('argv_file', 'argv_minmin', 'argv_minmin_plus', 'argv_plus_file'):
    o, n = by[name]
    if UNKNOWN in o[0]:
        fail.append('%s: the input binary already refused it, so this proves nothing' % name)
    if UNKNOWN not in n[0]:
        fail.append('%s: it is not an unknown option now' % name)
o, n = by['argv_file']
if 'exit 0' not in o[0] or len(o[1]) < 500:
    fail.append('argv_file: the input binary did not open a buffer and draw (%d bytes)' % len(o[1]))
o, n = by['argv_files']
if 'Too many edit arguments' not in o[0]:
    fail.append('argv_files: the input binary did not answer ME_TOO_MANY_ARGS, '
                'so removing that row proves nothing')
if 'Too many edit arguments' in n[0] or UNKNOWN not in n[0]:
    fail.append('argv_files: the second file argument is not an unknown option now')
o, n = by['argv_minus']
if 'blocked' not in o[0]:
    fail.append('argv_minus: the input binary did not take stdin over, so this proves nothing')
if 'blocked' in n[0] or UNKNOWN not in n[0]:
    fail.append('argv_minus: a bare `-` is not an unknown option now')
# `--` and `-- +q!` disagreed with each other before, because `+q!` after `--` was
# a file name; they agree now, and that is the whole of what `--` did.
if by['argv_minmin'][0][0] == by['argv_minmin_plus'][0][0]:
    fail.append('the input binary read `--` and `-- +q!` the same, so `--` was not ending the options')
if by['argv_minmin'][1][0] != by['argv_minmin_plus'][1][0]:
    fail.append('`--` and `-- +q!` still differ, so something still ends the options')
# The three that must not move are required to be doing something, not failing
# identically: `-T xterm` starts and draws, `+q!` quits at once.
for name in ('argv_T_xterm', 'argv_none'):
    o, n = by[name]
    if 'exit 0' not in n[0] or len(n[1]) < 500:
        fail.append('%s: the new binary did not start and draw' % name)
o, n = by['argv_plus_q']
if 'exit 0' not in n[0]:
    fail.append('argv_plus_q: `+q!` no longer runs and quits')
o, n = by['argv_T']
if 'Argument missing after' not in n[0]:
    fail.append('argv_T: a bare -T is not mainerr_arg_missing now')
o, n = by['argv_Txterm']
if 'Garbage after option argument' not in n[0]:
    fail.append('argv_Txterm: -Txterm is not ME_GARBAGE now -- the renumbering is wrong')
o, n = by['argv_plus_paste']
if 'exit 0' not in n[0] or 'hello' not in n[0]:
    fail.append("argv_plus_paste: `+set paste` and typing under it no longer work")

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    print('  %-12s a probe that cannot fail is not evidence, and one that fails' % '')
    print('  %-12s differently is not this probe.' % '')
    sys.exit(1)
print('  %-12s probes: %d moved (%s), %d unchanged' % (TAG, len(moved), ' '.join(moved), len(static)))
PY

# --- 7. a real terminal, where none of this went through a pipe --------------------
python3 - "$state/old" "$bin" <<'PY'
import os, sys, tempfile
sys.path.insert(0, 'tools')
import ptyrun
TAG = 'noargv'
ESC = b'\x1b'
home = tempfile.mkdtemp(prefix='zero5-home-')
env = dict(os.environ, HOME=home, VIM=os.path.join(home, 'novim'),
           VIMRUNTIME=os.path.join(home, 'novim'),
           XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
for k in ('VIMINIT', 'EXINIT', 'MYVIMRC'):
    env.pop(k, None)


def session(binary, args, keys):
    d = tempfile.mkdtemp(prefix='zero5-pty-')
    open(os.path.join(d, 'f.txt'), 'w').write('one\ntwo\nthree\n')
    text, status = ptyrun.session(binary, args, keys, term='xterm', cwd=d,
                                  settle=0.6, env=env)
    return text.decode('utf-8', 'replace'), status


# A file on the command line, on a real terminal: the old binary edits it, the new
# one refuses before the screen exists.
fa = [session(b, ['f.txt'], [b'Gdd', b':q!\r']) for b in (sys.argv[1], sys.argv[2])]
if 'three' not in fa[0][0]:
    sys.exit('  %-12s the input binary did not open the file on a pty -- this proves nothing' % TAG)
if 'Unknown option argument' not in fa[1][0]:
    sys.exit('  %-12s the new binary did not refuse the file argument on a pty' % TAG)
# ptyrun returns the raw wait status, not the exit code: mainerr()'s mch_exit(1)
# arrives here as 256.
if fa[1][1] != 256:
    sys.exit('  %-12s the refused file argument left wait status %s, expected 256 (exit 1)'
             % (TAG, fa[1][1]))

# And an ordinary editing session with no arguments, which must be the same on both.
edit = [session(b, [], [b'ityped here\x1b', b'0dw', b':set ruler?\r', b':q!\r'])
        for b in (sys.argv[1], sys.argv[2])]
if 'here' not in edit[0][0] or 'ruler' not in edit[0][0]:
    sys.exit('  %-12s the editing pty session did not edit on the input binary' % TAG)
if edit[0] != edit[1]:
    sys.exit('  %-12s the editing pty session moved: %r -> %r' % (TAG, edit[0][1], edit[1][1]))
print('  %-12s pty: the file argument edited by the old binary and refused by the new; '
      'the editing session identical either side' % TAG)
PY

# --- 8. the instrument this phase broke, and the one that replaced it --------------
# tools/termcheck.py asks its question with a file argument, so from this boundary
# it records nineteen empty rows.  `ztermcheck` is the same tool with its
# ask() replaced; it must record the BASELINE from the binary this phase was handed,
# which is what makes the swap a change of instrument and not of recording.
base=.reference/zero-baselines/ref-term.txt
tools/st.sh ztermcheck "$state/old" "$tmp/term-old" >/dev/null
cmp -s "$base" "$tmp/term-old" || {
    echo "  noargv       ztermcheck does not record the baseline from the input binary:"
    diff "$base" "$tmp/term-old" | head -5 | sed 's/^/               /'
    exit 1; }
python3 tools/termcheck.py "$bin" "$tmp/term-file" >/dev/null
if ! grep -q '(none)' "$tmp/term-file"; then
    echo "  noargv       tools/termcheck.py still works on this binary -- then the file"
    echo "               argument was not removed, and zrecord.sh need not have changed"
    exit 1
fi
echo "  noargv       terminal table: ztermcheck records the baseline's $(grep -c '' "$base") rows from the input binary; termcheck's file argument now gives $(grep -c '(none)' "$tmp/term-file") empty ones"
