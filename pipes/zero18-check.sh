#!/bin/sh
# Zero phase 18, the check -- main() is demoted to vim_main().
# See pipes/zero18-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero18-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero18-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# and `old`, that source built with the boundary's own flags.
#
# WHAT IS CLAIMED is that the editor now runs one call frame deeper and nothing else
# is different.  There are three things that could make that false and each has its
# own assertion:
#
#   * the LINKAGE.  `vim_main` must be static, so `nm --extern-only --defined-only`
#     still prints exactly `main` -- which tools/phasecheck.sh asserts for every zero
#     phase and which section 3 re-states here in the phase's own words.
#   * the LIBC SURFACE.  A phase that frees nothing says so as an EQUALITY, the way
#     phases 7, 8, 11, 12 and 16 do: the undefined set before and after is compared
#     with `cmp` and must be the same 33 names in the same order, not the same COUNT.
#   * the EXIT STATUS.  `return vim_main(argc, argv);` is a value this phase put in
#     the program's path that was not there before, so every way the editor can end
#     is probed on BOTH binaries and required to agree: `:q!` 0, `:cq 3` 3, EOF 1, a
#     bad option 1, SIGTERM 1, SIGHUP 1.
#
# AND THE PROBE IS PROVEN ABLE TO FAIL.  A table of six statuses that agree proves
# nothing unless a wrong status would have been caught, so the output is built a
# SECOND time with `mch_exit`'s `exit(r)` changed to `exit(r + 1)` -- one character --
# and every one of the six is required to MOVE.  That is phase 17's `SA_NODEFER`
# control in this phase's shape: the same source with the reason removed.
#
# THE BINARY IS NOT BYTE-IDENTICAL AND IS NOT ASSERTED TO BE.  At -O0 a call frame is
# real code: `main` now pushes a frame and calls `vim_main`, where it used to be
# `vim_main`'s body outright.  Measured, both built SOURCE_DATE_EPOCH=0 with the
# boundary's flags: 805,544 bytes either side -- the same SIZE, absorbed by alignment
# padding, and different bytes.  So the size is reported and the identity is not
# claimed; what is compared is the symbol set, the exit statuses and the recording.
set -eu

work=${1:?usage: zero18-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero18-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# --- 1. the control build, started first because it is the slowest thing here ---------
# ONE CHARACTER, and it is the reason the six statuses below are a measurement.
sed 's/^    exit(r);$/    exit(r + 1);/' "$f" > "$tmp/off.c"
cmp -s "$f" "$tmp/off.c" && { echo "  demote       the control edit changed nothing -- mch_exit's \`exit(r);\` is not where this phase expects it"; exit 1; }
[ "$(grep -c '^    exit(r + 1);$' "$tmp/off.c")" = 1 ] \
    || { echo "  demote       the control edit did not land exactly once"; exit 1; }
# shellcheck disable=SC2086
( gcc $cflags $ldflags -o "$tmp/off" "$tmp/off.c" ) &
pid_off=$!

# --- 2. the source -------------------------------------------------------------------
python3 - "$f" "$state/old.c" <<'PY'
import re, sys
TAG = 'demote'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
fail = []


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


# THE INPUT, so that this is a check on the phase and not on whatever it was handed.
HEAD = '\n    int\nmain\n(int argc, char **argv)\n{\n'
if old.count(HEAD) != 1:
    fail.append("the input did not hold exactly one three-line main() head, so this is "
                'not the file the phase was written against')
if mentions(old, 'vim_main'):
    fail.append('`vim_main` was already a word in the input, and this phase introduces it')

# THE OUTPUT.  vim_main is STATIC -- that is the whole of why `main` is still the only
# external symbol, and section 3 asserts the symbol itself.
if new.count('    static int\nvim_main(int argc, char **argv)\n{\n') != 1:
    fail.append('the output does not define `static int vim_main(int argc, char **argv)` '
                'exactly once.  It must be STATIC: nothing outside this file calls it, '
                'and a non-static one would be the first external symbol zero has ever '
                'added')
if HEAD in new:
    fail.append("main()'s three-line head survives in the output")
LAUNCH = ('\n    int\nmain(int argc, char **argv)\n{\n'
          '    return vim_main(argc, argv);\n}\n')
if not new.endswith(LAUNCH):
    fail.append('zero-vim.c does not end with the six-line launcher.  CLAUDE.md states '
                'that main() is literally the last thing in this file and its closing '
                'brace the final line, and that stays true')
if new.count(LAUNCH) != 1:
    fail.append('the launcher occurs %d times, expected 1' % new.count(LAUNCH))

# THE THREE WORDS, one by one.  A substring grep confuses all three and this does not.
for name, want, why in (
        ('main', 1, "the launcher's head, and it is the ONLY bare `main` in 80,000 "
                    'lines -- `main_loop`, `main_errors`, `vim_main` and `vim_main2` '
                    'are different words'),
        ('vim_main', 2, 'its definition and the one call from the launcher.  A third '
                        'would be a prototype, and a function defined above its only '
                        'call needs none'),
        ('vim_main2', 2, "upstream's second half of main(): its definition and the call "
                         'at the end of vim_main().  This phase does not touch it')):
    if mentions(new, name) != want:
        fail.append('`%s` as a whole word has %d mentions, expected %d -- %s'
                    % (name, mentions(new, name), want, why))
if new.count('    static int\nvim_main2(void)\n{\n') != 1:
    fail.append('vim_main2() moved, and this phase does not touch it')
if not re.search(r'\n    return vim_main2\(\);\n\}\n\n    int\nmain', new):
    fail.append('vim_main() does not end in `return vim_main2();` immediately above the '
                'launcher -- the body is meant to be untouched and the launcher '
                'appended after it')

# NOTHING ELSE MOVED.  Five lines, and the diff is two hunks.
if len(new.split('\n')) != len(old.split('\n')) + 5:
    fail.append('the file gained %d lines, expected 5 -- the fossil head lost one and '
                'the launcher added six'
                % (len(new.split('\n')) - len(old.split('\n'))))
if runs(new) != runs(old):
    fail.append('runs of two blank lines: %d in the output against %d in the input'
                % (runs(new), runs(old)))
# The body is the same text either side of the head, character for character.
body_old = old[old.index(HEAD) + len(HEAD):]
body_new = new[new.index('vim_main(int argc, char **argv)\n{\n'):]
body_new = body_new[body_new.index('{\n') + 2:len(body_new) - len(LAUNCH)]
if body_old != body_new:
    fail.append("the demoted function's body is not the bytes main()'s was")

# The tables and the directive count this phase does not touch.
sys.path.insert(0, 'tools')
# tools/create_cmdidxs.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
import create_cmdidxs
rows = re.findall(r'^    \[CMD_\w+\] = \{.*$', new, re.M)
if len(rows) != 98 or len(create_cmdidxs.names(sys.argv[1])) != 98:
    fail.append('cmdnames[] is not the 98 rows phase 10 left')
i = new.find('static struct vimoption options[]')
j = new.index('\n};', i)
if len(re.findall(r'^[ \t]*\{"([a-z]+)",', new[i:j], re.M)) != 108:
    fail.append('options[] is not the 108 rows phase 12 left')
d = [l for l in new.split('\n') if l.startswith('#')]
if len(d) != 12 or any(not l.startswith('#include <') for l in d):
    fail.append('the output does not have exactly the twelve `#include` directives '
                'phase 16 left -- this phase adds no header, and that is the point of '
                'doing the demotion before anything that might')
if re.search(r'\bexit\b', new) and len(re.findall(r'^\s*exit\(', new, re.M)) != 1:
    fail.append("`exit(` is not at exactly one statement -- mch_exit's `exit(r);`, "
                "which phase 17 left as the file's only one and which is the NEXT "
                "phase's, not this one's")
if mentions(new, '_exit'):
    fail.append('`_exit` is back, and phase 17 took it to zero')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s main() is now `static int vim_main(int argc, char **argv)` with its body '
      'unchanged BYTE FOR BYTE, and the last six lines of the file are a launcher whose '
      'whole content is `return vim_main(argc, argv);`.  +5 lines and two hunks' % TAG)
print('  %-12s the three words one by one, because a substring grep confuses them: '
      '`main` 1 -- the launcher, and the only bare `main` in the file -- `vim_main` 2, '
      'its definition and the one call, and `vim_main2` 2, which is upstream\'s and '
      'does not move.  No prototype for vim_main: it is defined above its only call'
      % '')
print('  %-12s and `exit(` is still at exactly one statement, mch_exit\'s `exit(r);` '
      "-- this phase does not touch it, and the twelve #includes are phase 16's" % '')
PY

# --- 3. the compile, the linkage and the libc surface ---------------------------------
# A PHASE THAT FREES NOTHING SAYS SO AS AN EQUALITY.  `cmp` on the two sorted sets, not
# a count: two sets of the same size can differ.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
if ! cmp -s "$tmp/before.u" .cache/symbols/last/undefined; then
    echo "  demote       the libc surface moved, and this phase frees nothing and adds nothing:"
    echo "               gone: $(comm -23 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    echo "               came: $(comm -13 "$tmp/before.u" .cache/symbols/last/undefined | tr '\n' ' ')"
    exit 1
fi
grep -qx exit .cache/symbols/last/undefined \
    || { echo "  demote       exit went, and it is the NEXT phase's: this one moves main() and nothing else"; exit 1; }
# ZERO-PLAN.md 4b's invariant, re-asserted for free.
for absent in open creat openat stat access fcntl getcwd strerror fopen fdopen \
              opendir fclose getc putc fsync _exit; do
    if grep -qx "$absent" .cache/symbols/last/undefined; then
        echo "  demote       $absent is undefined, and the core has had no way to open a file since phase 13"; exit 1
    fi
done
echo "  demote       symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), the two sets IDENTICAL as a cmp and not merely the same size -- moving the entry point is not a libc question, and 'exit' is still undefined because mch_exit still calls it"

# --- 4. the binary --------------------------------------------------------------------
make -C "$work" clean >/dev/null 2>&1 || true
[ -e "$work/zero-vim" ] && { echo "  build        the clean did not remove zero-vim"; exit 1; }
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$bin") bytes against the input's $(stat -c%s "$state/old") -- NOT asserted equal: at -O0 an extra call frame is real code"

# --- 5. every way the editor can end, on both binaries and on the control -------------
wait $pid_off || { echo "  demote       the control build did not compile"; exit 1; }
[ -x "$tmp/off" ] || { echo "  demote       the control build is missing"; exit 1; }

python3 - "$state/old" "$bin" "$tmp/off" <<'PY'
import concurrent.futures
import os
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, 'tools')
import zstream

TAG = 'demote'
old_bin, new_bin, off_bin = sys.argv[1], sys.argv[2], sys.argv[3]
fail = []


def env_for(home):
    env = dict(os.environ)
    env.update(TERM='xterm', HOME=home, VIM=os.path.join(home, 'novim'),
               VIMRUNTIME=os.path.join(home, 'novim'),
               XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    return env


def quiet(binary, args):
    """Run to completion with stdin at /dev/null and give back the status.

    /dev/null AND NOT A PIPE, and that is a measurement rather than a preference: with
    stdin a pipe the harness closes, the EOF case came back as a twenty-second timeout
    on four binaries out of five and as a clean 1 on the fifth -- a race in the
    HARNESS, not in the editor.  A file that is already at end of file has no race in
    it, and the four statuses below are then deterministic over repeated runs.
    """
    vim = zstream.stage(binary)     # argv[0], and the copy race: tools/zstream.py
    home = tempfile.mkdtemp(prefix='zero18-home-')
    try:
        with open(os.devnull, 'rb') as devnull:
            p = subprocess.run([vim] + list(args), stdin=devnull,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               env=env_for(home), timeout=20, start_new_session=True)
        return p.returncode
    except subprocess.TimeoutExpired:
        return 'TIMEOUT'
    finally:
        shutil.rmtree(home, ignore_errors=True)


def signalled(binary, sig):
    """Start the editor on pipes, let it draw, then signal it.  Give back the status.

    It waits for the editor to have DRAWN the typed text and then gone quiet, rather
    than for a clock: a fixed sleep signals the editor wherever its redraw had got to,
    which under load is a recording of the machine and not of the program.  A session
    that never draws is reported rather than compared.
    """
    vim = zstream.stage(binary)
    home = tempfile.mkdtemp(prefix='zero18-home-')
    p = subprocess.Popen([vim, '+set paste'], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         env=env_for(home), start_new_session=True)
    try:
        p.stdin.write(b'ihello')
        p.stdin.flush()
    except OSError:
        pass
    drawn = b''
    last, deadline = time.time(), time.time() + 20.0
    while True:
        if time.time() > deadline:
            drawn += b'<<NEVER DREW>>'
            break
        r, _, _ = select.select([p.stdout.fileno()], [], [], 0.05)
        if r:
            chunk = os.read(p.stdout.fileno(), 65536)
            if not chunk:
                break
            drawn += chunk
            last = time.time()
        elif b'hello' in drawn and time.time() - last > 0.3:
            break
    try:
        os.kill(p.pid, sig)
    except ProcessLookupError:
        pass
    try:
        p.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        p.kill()
        p.communicate()
    shutil.rmtree(home, ignore_errors=True)
    return 'NEVER DREW' if b'<<NEVER DREW>>' in drawn else p.returncode


# THE SIX WAYS THE EDITOR CAN END, and each is a different one of ZERO-PLAN.md's
# termination routes: ex_quit, ex_cquit, read_error_exit, mainerr and deathtrap twice.
WAYS = [
    ('quit',    lambda b: quiet(b, ['+q!']),   0, ':q! -- ex_quit -> getout(0)'),
    ('cquit3',  lambda b: quiet(b, ['+cq 3']), 3, ':cq 3 -- ex_cquit -> getout(3)'),
    ('eof',     lambda b: quiet(b, []),        1, 'end of input -- read_error_exit -> preserve_exit -> getout(1)'),
    ('badopt',  lambda b: quiet(b, ['-Z']),    1, 'a bad option -- mainerr -> mch_exit(1)'),
    ('sigterm', lambda b: signalled(b, signal.SIGTERM), 1, 'SIGTERM -- deathtrap -> preserve_exit -> getout(1)'),
    ('sighup',  lambda b: signalled(b, signal.SIGHUP),  1, 'SIGHUP -- deathtrap -> preserve_exit -> getout(1)'),
]
JOBS = [(w, tag, b) for w in WAYS for tag, b in
        (('old', old_bin), ('new', new_bin), ('off', off_bin))]
with concurrent.futures.ThreadPoolExecutor(max_workers=len(JOBS)) as ex:
    got = dict(zip([(j[0][0], j[1]) for j in JOBS],
                   ex.map(lambda j: j[0][1](j[2]), JOBS)))

rows = []
for name, _fn, want, why in WAYS:
    o, n, c = got[(name, 'old')], got[(name, 'new')], got[(name, 'off')]
    rows.append('%s=%s' % (name, n))
    if o != want:
        fail.append('the binary this phase was HANDED exited %s on %s, expected %d -- '
                    'so the agreement below would be two wrong answers agreeing'
                    % (o, why, want))
    if n != o:
        fail.append('%s: the input exited %s and the output %s.  Demoting main() must '
                    'not move a status -- `return vim_main(argc, argv);` is a value in '
                    'the path that was not there before' % (why, o, n))
    # THE CONTROL.  `exit(r + 1)` must move EVERY one of the six; a probe that cannot
    # report a wrong status is not measuring the right ones either.
    if c == n:
        fail.append('the control -- the output with mch_exit\'s `exit(r)` changed to '
                    '`exit(r + 1)`, ONE character -- also exited %s on %s, so this row '
                    'of the table is not measuring anything' % (c, why))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s every way the editor can end, the same on both binaries: %s -- ex_quit, '
      'ex_cquit, read_error_exit, mainerr and deathtrap twice, which is every route '
      'ZERO-PLAN.md maps that a phase can reach from outside'
      % (TAG, '  '.join(rows)))
print('  %-12s and the table is PROVEN able to fail: the output built a second time '
      "with mch_exit's `exit(r)` changed to `exit(r + 1)` -- one character -- moves "
      'ALL SIX (%s).  Six statuses that agree prove nothing unless a wrong one would '
      'have been caught'
      % ('', '  '.join('%s=%s' % (w[0], got[(w[0], 'off')]) for w in WAYS)))
PY

# tools/phaserun.sh runs tools/zerodelta.sh --phase 18 after this check, and this
# phase declares NOTHING: the corpus must not move at all.
