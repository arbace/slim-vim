#!/bin/sh
# Zero phase 30, the check -- the message fold.
# See pipes/zero30-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero30-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero30-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# and `old`, that source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# WHAT IS CLAIMED, in seven parts:
#
#   ARITHMETIC  computed FROM THE INPUT: the fold is +1 line and the sweep takes 91,
#               `msg_puts_printf` and `vim_strlen_maxlen` go 3 -> 0, TWO function
#               definitions leave, `msg_use_printf` STAYS at 6 -- the test is alive
#               and only the arm went -- the eleven directives are where they were,
#               and tools/canon.sh is a NO-OP.
#   THE PAIR    the phase's whole positive evidence, and it is phase 12's shape
#               because this is phase 12's kind of dead.  The INPUT source built
#               twice, once with `write(2, "PP-ENTERED\n", 11)` as the first statement
#               of `msg_puts_printf()` and once with the IDENTICAL instrument in
#               `msg_puts_display()`: 0 of 106 records against 103 of 106.  A
#               prediction about a branch nothing takes has nothing but an instrument
#               to confirm it.
#   STILL TRUE  and the other half of "which kind of dead".  `msg_use_printf()` is NOT
#               dead: instrumented on THIS PHASE'S OWN OUTPUT it answers TRUE 23
#               times, every one at `msg_clr_eos_force()` and every one in
#               ref-argv.txt's `mainerr` rows -- and `full_screen` is FALSE in all 23,
#               so the body it guards does nothing.  0 of 23, measured at the arm.
#   PROBES      32 stream probes and 4 deadly-signal probes, IDENTICAL on the binary
#               this phase was handed and on its own.  Every one of the 32 is a way of
#               making `msg_use_printf()` TRUE: at `t_TI` (`-T debug`, `:set t_ti=X`
#               five ways, `+set t_ti=X`, `:set term=debug`), at `termcap_active`
#               (`:stop`, `:set term=...`, which calls clear_termoptions() ->
#               stoptermcap(), and the stoptermcap() inside mch_exit), at `full_screen`
#               (SIGHUP/SIGTERM, whose deathtrap() clears it) and at `screen_valid`
#               (`:set lines=1`, `:set columns=1`).
#   THE TWO     THE FINDING THIS PHASE OWES, AND IT IS A RESULT AND NOT AN OMISSION.
#               Three further folds are built HERE, from this phase's own output, and
#               every one of them MUST MOVE a probe: `msg_clr_eos_force()` folded to
#               its false arm, the same site guarded by `msg_check_screen()` instead,
#               and `exit_scroll()`'s printf arm folded to `out_char('\n')`.  The
#               first two are the bug a corpus-only check would ship; the third is
#               ALIVE and phase 21 named it dead.
#   SYMBOLS     `nm -u` is THE SAME SET, as a `comm` empty in BOTH directions, and
#               `main` is the only external symbol.  Phase 21 already took `printf`,
#               `fprintf`, `fflush` and `stderr`, so removing their last non-caller
#               frees nothing: the assertion is an EQUALITY, which phase 21 predicted
#               in as many words.
#   THE CUT     `make editor.c`'s rule, run here: the prefix above the first
#               `#include` is 0 directives, 0 errors under `-fsyntax-only`, and its
#               warning set -- the core -> host boundary -- is compared WITH THE
#               INPUT'S, name by name, at run time.  It is never written out: phase 28
#               renames one of those names, and a check that spelled the set would
#               fail on a tree that is exactly right (ZERO-GOAL.md, "count them as a
#               rule and not as a table of constants").
#
# THE RECORDING CANNOT FAIL THIS PHASE AND CANNOT PASS IT EITHER, and that is stated
# rather than discovered.  All three rejected folds record BYTE-IDENTICALLY too --
# `screen_fill()` returns early on `ScreenLines == nullptr`, and `ScreenLines` is NULL
# in all 23 `mainerr` cases, which are the only 23 places the predicate is ever TRUE
# in a recording.  So `diff -r` is necessary here and is not the check; the
# instrumented pair and the 36 probes are.
set -eu

work=${1:?usage: zero30-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero30-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# The product build is written first and waited for below: it is seconds of wall time
# the assertions can be spending instead.
# shellcheck disable=SC2086
( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/new" "$f" ) &
pid_new=$!

# --- 0. the five other binaries this check is made of -----------------------------------
python3 - "$f" "$state/old.c" "$tmp" <<'PY'
import sys

TAG = 'msgfold'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
out = sys.argv[3]


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


files = {}

# cA, cB -- THE FOLD THAT CANNOT BE MADE SAFELY, twice: once to the false arm outright
# and once with `msg_check_screen()` in place of the test, which is the cheaper
# spelling that is NOT the same thing.  Both must move a probe, and the second must
# move the SAME probes, because what it drops is the `swapping_screen() &&
# !termcap_active` disjunct and that disjunct is exactly what t_ti_stopterm reaches.
A = 'msg_clr_eos_force(void)\n{\n    if (msg_use_printf())'
if new.count(A) != 1:
    die('msg_clr_eos_force\'s test is not in the output exactly once, so the two '
        'controls that make this phase\'s central finding would not be controls')
files['cA'] = new.replace(A, 'msg_clr_eos_force(void)\n{\n    if (0)', 1)
files['cB'] = new.replace(A, 'msg_clr_eos_force(void)\n{\n    if (!msg_check_screen())',
                          1)

# cC -- exit_scroll's printf arm folded to the else arm it already has.  It MUST move
# three stream probes and three signal probes; that is the evidence that this phase
# left it alone, and it is the measurement that corrects phase 21.
S4 = '''        if (msg_use_printf())
        {
            if (info_message)
            {
                host_message("\\n", -1, FALSE);
            }
            else
            {
                host_message("\\r\\n", -1, TRUE);
            }
        }
        else
        {
            out_char('\\n');
        }
'''
if new.count(S4) != 1:
    die('exit_scroll\'s printf arm is not in the output exactly once, so the control '
        'that shows it is ALIVE would not be a control')
files['cC'] = new.replace(S4, "        out_char('\\n');\n", 1)

# i_pp, i_ctl -- THE INSTRUMENTED PAIR, on the source this phase was HANDED.  The same
# eleven bytes at two places: the function this phase removes, and the function the
# other arm calls.  One must mark nothing and the other almost everything.
MARK = '    write(2, "PP-ENTERED\\n", 11);\n'
P = 'msg_puts_printf(char_u *str, int maxlen)\n{\n'
D = ('msg_puts_display(char_u      *str, int         maxlen, int         attr, '
     'int         recurse)\n{\n')
for tag, head in (('i_pp', P), ('i_ctl', D)):
    if old.count(head) != 1:
        die('%s\'s definition is not in the INPUT exactly once, so the instrumented '
            'pair would not be a pair' % head.split('(')[0])
    files[tag] = old.replace(head, head + MARK, 1)

# i_s3 -- the predicate on THIS PHASE'S OWN OUTPUT, at the one site where it is ever
# TRUE, and at the arm inside it.  23 and 0 is what says this is phase 12's kind of
# dead and not phase 9's.
C = ('msg_clr_eos_force(void)\n{\n    if (msg_use_printf())\n    {\n'
     '        if (full_screen)\n        {\n')
if new.count(C) != 1:
    die('msg_clr_eos_force\'s two nested tests are not in the output exactly once')
files['i_s3'] = new.replace(C, 'msg_clr_eos_force(void)\n{\n    if (msg_use_printf())\n'
                               '    {\n        write(2, "T-cleos\\n", 8);\n'
                               '        if (full_screen)\n        {\n'
                               '            write(2, "C-fullscreen\\n", 13);\n', 1)

for name, text in files.items():
    if text == new and text == old:
        die('%s changed nothing' % name)
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(text)
print('  %-12s six controls written: cA msg_clr_eos_force folded to its false arm, cB '
      'the same site guarded by msg_check_screen() instead, cC exit_scroll\'s printf '
      'arm folded to out_char, i_pp and i_ctl the instrumented pair on the INPUT, '
      'i_s3 the predicate instrumented on this phase\'s own output' % TAG)
PY

for v in cA cB cC i_pp i_ctl i_s3; do
    # shellcheck disable=SC2086
    ( SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o "$tmp/$v" "$tmp/$v.c" ) &
done
# tools/canon.sh must be a NO-OP: the two lines the fold writes are new text, and
# canon is what says they are written the way this file writes everything else.
cp "$f" "$tmp/canon.c"
( tools/canon.sh "$tmp/canon.c" >"$tmp/canon.log" 2>&1 ) &
pid_canon=$!

# The probe harnesses, written once and used by both halves of section 5.
cat > "$tmp/zprobe.py" <<'PY'
"""Thirty-two ways of making msg_use_printf() TRUE, on a pipe."""
import hashlib
import re
import sys

sys.path.insert(0, 'tools')
import zstream

# It is TRUE when `!msg_check_screen()` -- full_screen FALSE or screen_valid(FALSE)
# FALSE -- or when `swapping_screen() && !termcap_active`, and swapping_screen() needs
# t_TI non-empty.  MEASURED: exactly one KS_TI row exists in all nine built-in terminal
# tables, `{(int)KS_TI, "[TI]"}` in builtin_debug[].  So the probes attack t_TI,
# termcap_active, full_screen and screen_valid, each by every route the editor has.
PROBES = [
    ('T_debug',        dict(args=('-T', 'debug'), keys=[b':set nosuchopt\r', b':q!\r'])),
    ('T_debug_quit',   dict(args=('-T', 'debug'), keys=[b'ihello\x1b', b':q!\r'])),
    ('T_dumb',         dict(args=('-T', 'dumb'),  keys=[b':set nosuchopt\r', b':q!\r'])),
    ('t_ti_set_err',   dict(keys=[b':set t_ti=X\r', b':set nosuchopt\r', b':q!\r'])),
    ('t_ti_te_quit',   dict(keys=[b':set t_ti=X t_te=Y\r', b':q!\r'])),
    ('t_ti_plus',      dict(args=('+set t_ti=X',), keys=[b':set nosuchopt\r', b':q!\r'])),
    ('t_ti_reglist',   dict(keys=[b':set t_ti=X\r', b':registers\r', b'q', b'\x1b', b':q!\r'])),
    ('t_ti_ctrl_g',    dict(keys=[b':set t_ti=X\r', b'\x07', b':q!\r'])),
    ('t_ti_modified',  dict(keys=[b':set paste\r', b'ix\x1b', b':set t_ti=X\r', b':q\r', b':q!\r'])),
    ('ctrl_c_clean',   dict(keys=[b'\x03'])),
    ('ctrl_c_changed', dict(keys=[b':set paste\r', b'ixyz\x1b', b'\x03'])),
    ('lines_1',        dict(keys=[b':set lines=1\r', b':set nosuchopt\r', b':q!\r'])),
    ('columns_1',      dict(keys=[b':set columns=1\r', b':set nosuchopt\r', b':q!\r'])),
    ('unknown_term',   dict(term='no-such-term-9x', keys=[b':set nosuchopt\r', b':q!\r'])),
    ('bad_option',     dict(args=('-y',), keys=[b''])),
    ('T_missing',      dict(args=('-T',), keys=[b''])),
    ('t_ti_more',      dict(keys=[b':set t_ti=X\r', b':set all\r', b'q', b'\x1b', b':q!\r'])),
    ('t_ti_hitenter',  dict(keys=[b':set t_ti=X\r', b':map\r', b'\r', b':q!\r'])),
    ('debug_more',     dict(args=('-T', 'debug'), keys=[b':set all\r', b'q', b'\x1b', b':q!\r'])),
    ('debug_hitenter', dict(args=('-T', 'debug'), keys=[b':map\r', b'\r', b':q!\r'])),
    ('t_ti_stopterm',  dict(keys=[b':set t_ti=X\r', b':set t_te=Y\r', b'ZQ'])),
    ('empty_keys',     dict(keys=[b''])),
    ('term_debug',      dict(keys=[b':set term=debug\r', b':set nosuchopt\r', b':q!\r'])),
    ('term_debug_x2',   dict(keys=[b':set term=debug\r', b':set term=debug\r', b':q!\r'])),
    ('term_unknown',    dict(keys=[b':set term=no-such-term-9x\r', b':q!\r'])),
    ('term_after_ti',   dict(keys=[b':set t_ti=X\r', b':set term=xterm\r', b':q!\r'])),
    ('term_from_debug', dict(args=('-T', 'debug'), keys=[b':set term=debug\r', b':q!\r'])),
    ('term_stop_debug', dict(args=('-T', 'debug'), keys=[b':stop\r', b':q!\r'])),
    ('term_plus_bad',   dict(args=('-T', 'debug', '+set nosuchopt'), keys=[b':q!\r'])),
    ('term_dumb_set',   dict(keys=[b':set term=dumb\r', b':set nosuchopt\r', b':q!\r'])),
    ('term_ti_then_ti', dict(keys=[b':set term=debug\r', b':set t_ti=X\r', b':set all\r', b'q', b'\x1b', b':q!\r'])),
    ('term_msg_after',  dict(keys=[b':set term=debug\r', b'\x07', b':q!\r'])),
]

# Two rows carry `compiled <date> <time>` from mainerr's banner, and two builds minutes
# apart differ in it and in nothing else.
STAMP = re.compile(rb'compiled [A-Z][a-z][a-z] [ 0-9][0-9] [0-9]{4} [0-9:]{8}')


def table(binary):
    rows = []
    for name, kw in PROBES:
        try:
            _, so, se, rc = zstream.session(binary, kw.get('keys', [b'']),
                                            term=kw.get('term', 'xterm'),
                                            args=kw.get('args', ()), timeout=20)
            so = STAMP.sub(b'compiled <date>', so)
            se = STAMP.sub(b'compiled <date>', se)
            rows.append('%-16s rc=%-8s out=%-6d sha=%s err=%-4d %r'
                        % (name, rc, len(so), hashlib.sha256(so).hexdigest()[:12],
                           len(se), se[:80]))
        except zstream.Blocked:
            rows.append('%-16s BLOCKED' % name)
    return rows


if __name__ == '__main__':
    open(sys.argv[2], 'w').write('\n'.join(table(sys.argv[1])) + '\n')
PY

cat > "$tmp/zsig.py" <<'PY'
"""Four deadly signals on a real pty, with fd 2 on a pipe of its own.

THE SEPARATE fd 2 IS THE WHOLE POINT.  exit_scroll()'s printf arm writes `\r\n` to
STDERR and its other arm writes the same two bytes to STDOUT, so on a pty where both
are the same device the combined stream is byte-identical either way -- which is
exactly why tools/zpty.py could never see it and why folding it would be undeclarable.
Split the descriptors and it is two bytes moving from one to the other.

The pty.fork() caveat .claude/briefs/zero-signals.md 2d records -- an orphaned process
group never reaches state T -- does not matter for a deadly signal.
"""
import fcntl
import hashlib
import os
import pty
import select
import shutil
import signal
import struct
import sys
import tempfile
import termios
import time

sys.path.insert(0, 'tools')
import zstream

CASES = [
    ('hup_clean', dict(keys=[b''], sig=signal.SIGHUP)),
    ('hup_msg',   dict(keys=[b'\x07'], sig=signal.SIGHUP)),
    ('term_msg',  dict(keys=[b'\x07'], sig=signal.SIGTERM)),
    ('hup_dbg',   dict(keys=[b'\x07'], sig=signal.SIGHUP, args=('-T', 'debug'))),
]


def run(binary, keys, sig=None, delay=0.6, term='xterm', args=(), rows=24, cols=80):
    vim = zstream.stage(binary)
    home = tempfile.mkdtemp(prefix='zsig-')
    env = dict(os.environ)
    env.update(TERM=term, HOME=home, VIM=home + '/novim', VIMRUNTIME=home + '/novim',
               XDG_CONFIG_HOME=home + '/xdg')
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    er, ew = os.pipe()
    pid, fd = pty.fork()
    if pid == 0:
        os.close(er)
        os.dup2(ew, 2)
        os.close(ew)
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
        os.chdir(home)
        os.execve(vim, [vim] + list(args), env)
    os.close(ew)
    out = b''
    err = b''

    def pump(t):
        nonlocal out, err
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([fd, er], [], [], 0.05)
            for x in r:
                try:
                    d = os.read(x, 65536)
                except OSError:
                    d = b''
                if x == fd:
                    out += d
                else:
                    err += d

    for k in keys:
        time.sleep(0.3)
        os.write(fd, k)
        pump(0.35)
    if sig:
        time.sleep(delay)
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            pass
    pump(2.0)
    try:
        _, st = os.waitpid(pid, 0)
    except ChildProcessError:
        st = -1
    os.close(fd)
    os.close(er)
    shutil.rmtree(home, ignore_errors=True)
    return out, err, st


if __name__ == '__main__':
    rows = []
    for name, kw in CASES:
        out, err, st = run(sys.argv[1], **kw)
        rows.append('%-12s st=%-6s out=%-6d sha=%s err=%-4d %r'
                    % (name, st, len(out), hashlib.sha256(out).hexdigest()[:12],
                       len(err), err[:40]))
    open(sys.argv[2], 'w').write('\n'.join(rows) + '\n')
PY

# --- 1. the source, as arithmetic on the input ------------------------------------------
python3 - "$f" "$state/old.c" "$before_lines" <<'PY'
import re
import sys

TAG = 'msgfold'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
before_lines = int(sys.argv[3])
fail = []


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


O = old.split('\n')
N = new.split('\n')
if len(O) - 1 != before_lines:
    fail.append('the state directory says the edit was handed %d lines and old.c has '
                '%d' % (before_lines, len(O) - 1))

# THE ARITHMETIC.  The edit adds one line; the sweep takes 76 for msg_puts_printf and
# its blank, 14 for vim_strlen_maxlen and its blank, and 2 prototypes.  Every part of
# that sum is asserted separately below, so a phase that removed the right number of
# lines from the wrong places could not pass.
CUT = 92
if len(O) - len(N) != CUT - 1:
    fail.append('the output is %d lines and the input was %d, a difference of %d where '
                '%d was expected -- the edit adds 1 and the sweep takes %d: 75 for '
                'msg_puts_printf and 1 blank, 13 for vim_strlen_maxlen and 1 blank, and '
                'the two prototypes'
                % (len(N) - 1, len(O) - 1, len(O) - len(N), CUT - 1, CUT))

# WHAT WENT, and WHAT DID NOT.  `msg_use_printf` at 6 in BOTH is the assertion that
# says which kind of phase this is: the predicate is alive and only one of its four
# arms was dead.
for name, o_want, n_want, why in (
        ('msg_puts_printf', 3, 0, 'a prototype, a definition and one call'),
        ('vim_strlen_maxlen', 3, 0, 'a prototype, a definition and its ONLY call, '
                                    'which was inside msg_puts_printf -- A CHECK THAT '
                                    'EXPECTS ONE FUNCTION REMOVED FAILS ON A CORRECT '
                                    'PHASE'),
        ('msg_use_printf', 6, 6, 'UNCHANGED, and it is the point: the test stays, is '
                                 'still TRUE 23 times in a recording, and only the arm '
                                 'behind it went.  A check that expected it at 0 would '
                                 'fail on a correct phase'),
        ('msg_puts_display', 4, 4, 'the false arm, untouched'),
        ('msg_clr_eos_force', 5, 5, 'untouched -- folding its test is measurably wrong'),
        ('exit_scroll', 3, 3, 'untouched -- its printf arm is ALIVE'),
        ('host_message', 10, 7, 'four calls inside msg_puts_printf left and one arrived'),
        ('info_message', 9, 7, 'four reads inside msg_puts_printf left and two arrived '
                               '-- it is a file-scope int and is in scope at the new '
                               'call site'),
        ('msg_didout', 29, 29, 'msg_puts_printf\'s last statement left and the '
                               'replacement writes it')):
    go, gn = mentions(old, name), mentions(new, name)
    if (go, gn) != (o_want, n_want):
        fail.append('`%s` is %d mentions in the input and %d in the output, where %d '
                    'and %d were expected -- %s' % (name, go, gn, o_want, n_want, why))

# THE FOLD ITSELF, and the three sites it did not touch, read back off the output.
NEWARM = ('    if (msg_use_printf())\n    {\n        host_message((char *)str, maxlen, '
          '!info_message);\n        msg_didout = TRUE;\n    }\n')
if new.count(NEWARM) != 1:
    fail.append('the folded arm is not in the output exactly once')
for who, text in (('hit_return_msg', '    if (!msg_use_printf())\n'),
                  ('msg_clr_eos_force',
                   'msg_clr_eos_force(void)\n{\n    if (msg_use_printf())\n'),
                  ('exit_scroll', '        if (msg_use_printf())\n')):
    if new.count(text) != 1:
        fail.append('the %s site is not in the output exactly once, and this phase '
                    'touches exactly ONE of the four call sites' % who)

# THE DIRECTIVES AND THE BOUNDARY.  Eleven, consecutive, the input's own, and none of
# them above the core.
od = [i for i, l in enumerate(O) if re.match(r'^ *#', l)]
nd = [i for i, l in enumerate(N) if re.match(r'^ *#', l)]
if len(od) != 11 or len(nd) != 11:
    fail.append('the input has %d directives and the output %d; both must be 11'
                % (len(od), len(nd)))
elif nd != list(range(nd[0], nd[0] + 11)):
    fail.append('the output\'s eleven directives are not on eleven consecutive lines')
elif [N[i] for i in nd] != [O[i] for i in od]:
    fail.append('the eleven directives are not the eleven the input had')
elif nd[0] - od[0] != len(N) - len(O):
    fail.append('the boundary moved by %d lines and the file by %d: the whole of this '
                'phase is above the first `#include`'
                % (nd[0] - od[0], len(N) - len(O)))

if runs(new) != runs(old):
    fail.append('the edit and the sweep left %d runs of two blank lines where there '
                'were %d' % (runs(new), runs(old)))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s %d lines -> %d: the edit adds ONE and the sweep takes %d -- '
      'msg_puts_printf\'s 75 and its blank, vim_strlen_maxlen\'s 13 and its blank, and '
      'the two prototypes.  TWO functions, not one: vim_strlen_maxlen\'s only call was '
      'inside msg_puts_printf' % (TAG, len(O) - 1, len(N) - 1, CUT))
print('  %-12s msg_puts_printf 3 -> 0 and vim_strlen_maxlen 3 -> 0, while '
      'msg_use_printf STAYS AT 6 and msg_clr_eos_force, exit_scroll and '
      'hit_return_msg\'s `!msg_use_printf()` are each still exactly one site.  The '
      'predicate is alive; ONE of its four arms was dead' % TAG)
print('  %-12s host_message 10 -> 7 and info_message 9 -> 7 -- four calls and four '
      'reads left with the function and one call and two reads arrived with the fold; '
      'msg_didout is 29 either side, the removed function\'s last statement being the '
      'replacement\'s second line' % TAG)
print('  %-12s the eleven directives are the input\'s own, consecutive, and the '
      'boundary moved by exactly the lines the file lost -- every line this phase '
      'touches is above the first `#include`.  Blank-line runs unmoved at %d'
      % (TAG, runs(new)))
PY

# --- 2. canon.sh, and the tools with floors ---------------------------------------------
wait $pid_canon || { echo "  msgfold      tools/canon.sh failed on the output:"; sed -n '1,10p' "$tmp/canon.log"; exit 1; }
if ! cmp -s "$f" "$tmp/canon.c"; then
    echo "  msgfold      tools/canon.sh is not a no-op on the output -- the two lines the fold writes are not written the way this file writes everything else:"
    diff "$f" "$tmp/canon.c" | sed -n '1,12p'
    exit 1
fi
echo "  msgfold      tools/canon.sh is a NO-OP on the output: the two lines the fold writes are written the way this file writes everything else"

tools/st.sh orphanopts "$f"
tools/st.sh nvidx "$f"
tools/st.sh zhostonly "$f"
python3 - "$f" <<'PY'
import sys
sys.path.insert(0, 'tools')
import create_cmdidxs
n = len(create_cmdidxs.names(sys.argv[1]))
if n != 98:
    sys.exit('  %-12s names() reads %d command rows and must read 98 -- this phase '
             'removes no Ex command' % ('msgfold', n))
print('  %-12s tools/create_cmdidxs.py\'s names() reads 98 rows, orphanopts '
      'and nvidx pass, and neither floor is approached: this phase '
      'removes no command, no option row and no normal-mode row' % 'msgfold')
PY

# --- 3. the symbols, and the binary -------------------------------------------------------
wait $pid_new || { echo "  msgfold      the output did not build with '$cflags' '$ldflags'"; exit 1; }
gcc -c -O0 -fno-stack-protector -o "$tmp/old.o" "$state/old.c"
gcc -c -O0 -fno-stack-protector -o "$tmp/new.o" "$f"
nm -u "$tmp/old.o" | awk '{print $2}' | sort > "$tmp/u.old"
nm -u "$tmp/new.o" | awk '{print $2}' | sort > "$tmp/u.new"
gone=$(comm -23 "$tmp/u.old" "$tmp/u.new" | tr '\n' ' ')
came=$(comm -13 "$tmp/u.old" "$tmp/u.new" | tr '\n' ' ')
if [ -n "$gone$came" ]; then
    echo "  msgfold      \`nm -u\` moved: gone [$gone] arrived [$came].  Phase 21 took printf, fprintf, fflush and stderr with the calls THEMSELVES, so removing the function that no longer made them frees nothing -- this is an EQUALITY and phase 21 predicted it"
    exit 1
fi
ext=$(nm --extern-only --defined-only "$tmp/new.o" | awk '{print $3}' | sort | tr '\n' ' ')
if [ "$ext" != "main " ]; then
    echo "  msgfold      the output defines external symbols other than main: $ext"
    exit 1
fi
echo "  msgfold      \`nm -u\` is THE SAME SET, $(wc -l <"$tmp/u.new") names, as a \`comm\` empty in BOTH directions, and \`main\` is still the only external symbol.  Removing 75 lines that call nothing libc has frees nothing, which is what phase 21 said when it took the four stdio symbols with the CALLS and left the function"
echo "  msgfold      the binary is $(stat -c%s "$tmp/new") bytes against the input's $(stat -c%s "$state/old")"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

# --- 4. the editor.c cut, and its warning set compared WITH THE INPUT'S --------------------
# `make editor.c`'s rule is one awk clause and no judgement; here it is run on both
# sides and the two prefixes are held to the same three properties.  THE THIRTEEN NAMES
# ARE NEVER WRITTEN OUT: phase 28 replaces `musl_gettimeofday` with `musl_now_ms`, and
# a check that spelled the set would fail on a tree that is exactly right.
for side in old new; do
    case $side in old) src=$state/old.c;; new) src=$f;; esac
    awk '/^ *# *include / { exit } { a[NR] = $0; if (NF) last = NR } \
         END { for (i = 1; i <= last; i++) print a[i] }' "$src" > "$tmp/ed.$side.c"
    if grep -q '^ *#' "$tmp/ed.$side.c"; then
        echo "  msgfold      the $side cut holds a directive, so it found the wrong line:"
        grep -n '^ *#' "$tmp/ed.$side.c" | head -3
        exit 1
    fi
    gcc -O0 -fno-stack-protector -Wall -Wextra -Wno-unused-parameter -fsyntax-only \
        "$tmp/ed.$side.c" 2>"$tmp/w.$side" || true
    if grep -q ': error:' "$tmp/w.$side"; then
        echo "  msgfold      the $side cut does not parse on its own:"
        grep ': error:' "$tmp/w.$side" | head -4
        exit 1
    fi
    grep -o "'[A-Za-z_][A-Za-z0-9_]*' used but never defined" "$tmp/w.$side" \
        | sed "s/' used.*//; s/^'//" | sort -u > "$tmp/b.$side"
    if grep ': warning: ' "$tmp/w.$side" | grep -qv 'used but never defined'; then
        echo "  msgfold      the $side cut has a warning that is not a boundary name:"
        grep ': warning: ' "$tmp/w.$side" | grep -v 'used but never defined' | head -3
        exit 1
    fi
done
if ! cmp -s "$tmp/b.old" "$tmp/b.new"; then
    echo "  msgfold      the core -> host boundary moved: gone [$(comm -23 "$tmp/b.old" "$tmp/b.new" | tr '\n' ' ')] arrived [$(comm -13 "$tmp/b.old" "$tmp/b.new" | tr '\n' ' ')].  This phase adds ONE call to host_message, which was already a boundary name"
    exit 1
fi
echo "  msgfold      the \`make editor.c\` cut: $(grep -c '' "$tmp/ed.old.c") lines -> $(grep -c '' "$tmp/ed.new.c"), 0 directives, 0 errors under \`-fsyntax-only\`, and the WHOLE warning set is the core -> host boundary -- $(wc -l <"$tmp/b.new") names, IDENTICAL to the input's, compared name by name at run time and never written out here (phase 28 renames one of them)"

# --- 5. the probes: 32 on a pipe and 4 on a pty, both sides ---------------------------------
wait
for v in old new cA cB cC; do
    case $v in old) b=$state/old;; *) b=$tmp/$v;; esac
    ( python3 "$tmp/zprobe.py" "$b" "$tmp/P.$v" ) &
done
for v in old new cA cC; do
    case $v in old) b=$state/old;; *) b=$tmp/$v;; esac
    ( python3 "$tmp/zsig.py" "$b" "$tmp/S.$v" ) &
done
# The five recordings go at the same time: two for the declared delta and three for the
# instrumented pair and the predicate.
tools/zrecord.sh "$state/old" "$state/old.c" "$tmp/REC.old" >/dev/null 2>&1 &
tools/zrecord.sh "$tmp/new" "$f" "$tmp/REC.new" >/dev/null 2>&1 &
tools/zrecord.sh "$tmp/i_pp" "$tmp/i_pp.c" "$tmp/REC.i_pp" >/dev/null 2>&1 &
tools/zrecord.sh "$tmp/i_ctl" "$tmp/i_ctl.c" "$tmp/REC.i_ctl" >/dev/null 2>&1 &
tools/zrecord.sh "$tmp/i_s3" "$tmp/i_s3.c" "$tmp/REC.i_s3" >/dev/null 2>&1 &
wait

if ! cmp -s "$tmp/P.old" "$tmp/P.new"; then
    echo "  msgfold      the declared delta is NOTHING AT ALL and the 32 stream probes differ:"
    diff "$tmp/P.old" "$tmp/P.new" | sed -n '1,12p'
    exit 1
fi
if ! cmp -s "$tmp/S.old" "$tmp/S.new"; then
    echo "  msgfold      the four deadly-signal probes differ, which is the one thing this phase is most likely to have broken by accident -- exit_scroll's arm:"
    diff "$tmp/S.old" "$tmp/S.new" | sed -n '1,12p'
    exit 1
fi
echo "  msgfold      MUST NOT DIFFER: all 32 stream probes identical on the binary this phase was handed and on its own -- every one a way of making msg_use_printf() TRUE, at t_TI, at termcap_active, at full_screen and at screen_valid"
echo "  msgfold      MUST NOT DIFFER: all 4 deadly-signal probes identical, on a real pty WITH FD 2 ON A PIPE OF ITS OWN -- hup_clean, hup_msg, term_msg, hup_dbg.  Three of the four reach exit_scroll's printf arm, so they are the evidence that this phase did not disturb it"

# THE FINDING, AND IT IS A RESULT AND NOT AN OMISSION: the three folds that look like
# this one and are not safe.  Each must move a named probe; if one of them ever stops
# moving, the reason this phase declined it has stopped being true and the phase should
# be reopened rather than quietly widened.
for v in cA cB; do
    case $v in
        cA) what="msg_clr_eos_force's test folded to its FALSE arm";;
        cB) what="msg_clr_eos_force's test replaced by msg_check_screen(), which drops the swapping_screen() && !termcap_active disjunct";;
    esac
    if cmp -s "$tmp/P.$v" "$tmp/P.new"; then
        echo "  msgfold      $v ($what) moves NONE of the 32 stream probes, so this phase's central finding -- that the fold cannot be made safely -- is no longer measured"
        exit 1
    fi
    d=$(diff "$tmp/P.new" "$tmp/P.$v" | grep -c '^>' || true)
    n=$(diff "$tmp/P.new" "$tmp/P.$v" | sed -n 's/^> \([A-Za-z_0-9]*\) .*/\1/p' | tr '\n' ' ')
    if [ "$n" != "t_ti_stopterm " ]; then
        echo "  msgfold      $v moves [$n] and was measured to move exactly t_ti_stopterm"
        exit 1
    fi
    echo "  msgfold      MUST DIFFER -- $v: $what.  It moves $d of the 32 probes, and it is $n: $(sed -n 's/^t_ti_stopterm  *rc=[0-9]*  *out=\([0-9]*\).*/\1/p' "$tmp/P.new") bytes -> $(sed -n 's/^t_ti_stopterm  *rc=[0-9]*  *out=\([0-9]*\).*/\1/p' "$tmp/P.$v")"
done
if cmp -s "$tmp/S.cA" "$tmp/S.new"; then
    echo "  msgfold      cA moves none of the four signal probes, and hup_clean was measured to go 2,124 -> 2,142"
    exit 1
fi
echo "  msgfold      AND THE SECOND MEASUREMENT OF THE SAME HAZARD: cA moves hup_clean, $(sed -n 's/^hup_clean  *st=[0-9]*  *out=\([0-9]*\).*/\1/p' "$tmp/S.new") bytes -> $(sed -n 's/^hup_clean  *st=[0-9]*  *out=\([0-9]*\).*/\1/p' "$tmp/S.cA"), the extra eighteen being an escape sequence that erases the last line of a screen the editor has just declared unusable, AFTER \`Vim: Finished.\`  THE CORPUS CANNOT SEE EITHER: screen_fill() returns early on ScreenLines == nullptr and it is NULL in all 23 mainerr cases, so a phase checked only against the recording would ship this"

sc=$(diff "$tmp/P.new" "$tmp/P.cC" | sed -n 's/^> \([A-Za-z_0-9]*\) .*/\1/p' | tr '\n' ' ')
if [ "$sc" != "t_ti_more debug_more term_ti_then_ti " ]; then
    echo "  msgfold      cC (exit_scroll's printf arm folded to out_char) moves [$sc] of the 32 stream probes and was measured to move exactly t_ti_more, debug_more and term_ti_then_ti"
    exit 1
fi
sg=$(diff "$tmp/S.new" "$tmp/S.cC" | sed -n 's/^> \([A-Za-z_0-9]*\) .*/\1/p' | tr '\n' ' ')
if [ "$sg" != "hup_msg term_msg hup_dbg " ]; then
    echo "  msgfold      cC moves [$sg] of the four signal probes and was measured to move exactly hup_msg, term_msg and hup_dbg"
    exit 1
fi
echo "  msgfold      MUST DIFFER -- cC: exit_scroll's printf arm folded to out_char('\\n').  IT IS ALIVE AND PHASE 21 WAS WRONG TO NAME IT A FOLLOW-UP BESIDE msg_puts_printf.  With NO SIGNAL AT ALL it moves [$sc] -- each \`:set t_ti=X\` or \`-T debug\`, a paged \`:set all\`, exit -- and with a signal it moves [$sg].  What moves is two bytes from FD 2 TO FD 1: out_char('\\n') emits \`\\r\` first, so the bytes on the wire are the same two, and on a pty where both descriptors are the same device the combined stream is byte-identical.  That is why tools/zpty.py cannot see it, why folding it would be UNDECLARABLE, and why it belongs to the phase that decides the core writes nothing to fd 2 at all"

# --- 6. the recording, and the instrumented pair -------------------------------------------
if ! diff -rq "$tmp/REC.old" "$tmp/REC.new" >"$tmp/rec.diff" 2>&1; then
    echo "  msgfold      the declared delta is NOTHING AT ALL and the two recordings differ:"
    sed -n '1,12p' "$tmp/rec.diff"
    exit 1
fi
echo "  msgfold      the declared delta is NOTHING AT ALL and TWO FULL RECORDINGS ARE BYTE-IDENTICAL -- 102 screen cases, every Ex command, every command line, the pty scenarios and the terminal table"

python3 - "$tmp" <<'PY'
import os
import sys

TAG = 'msgfold'
tmp = sys.argv[1]
fail = []


def marks(rec, token):
    hit, total, files = [], 0, 0
    for root, _, names in os.walk(rec):
        for n in names:
            p = os.path.join(root, n)
            files += 1
            try:
                d = open(p, 'rb').read()
            except OSError:
                continue
            c = d.count(token.encode())
            if c:
                hit.append(os.path.relpath(p, rec))
                total += c
    return sorted(hit), total, files


# THE PAIR.  The same eleven bytes at two places in the SAME source, so the instrument
# cannot be the difference -- only where it is.
pp, pp_n, n_rec = marks(tmp + '/REC.i_pp', 'PP-ENTERED')
ctl, ctl_n, _ = marks(tmp + '/REC.i_ctl', 'PP-ENTERED')
if n_rec < 100:
    fail.append('a recording is %d records, and a measurement over a corpus nothing '
                'wrote passes.  The count is REPORTED and not pinned: it was 106 when '
                'this phase was written -- 102 screen cases and four files -- and is '
                '122 since zero phase 40 added the memline corpus' % n_rec)
if pp:
    fail.append('the instrument inside msg_puts_printf() marks %d of %d records (%s), '
                'and the whole claim of this phase is that it marks NONE'
                % (len(pp), n_rec, ' '.join(pp[:4])))
if len(ctl) < 100:
    fail.append('the CONTROL -- the identical instrument in msg_puts_display() -- marks '
                'only %d of %d records, so the instrument is not working and the 0 '
                'above proves nothing' % (len(ctl), n_rec))

# STILL TRUE, on this phase's OWN output, and the other half of "which kind of dead".
tr, tr_n, _ = marks(tmp + '/REC.i_s3', 'T-cleos')
fs, fs_n, _ = marks(tmp + '/REC.i_s3', 'C-fullscreen')
if tr_n != 23 or tr != ['ref-argv.txt']:
    fail.append('msg_use_printf() answers TRUE %d times in %s and was measured at 23, '
                'all in ref-argv.txt -- one per mainerr row.  It is NOT dead and this '
                'phase does not claim it is' % (tr_n, ' '.join(tr) or 'nothing'))
if fs_n:
    fail.append('`full_screen` is TRUE %d times inside those 23, and was measured at 0: '
                'the body msg_use_printf() guards there does nothing' % fs_n)

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s THE INSTRUMENTED PAIR, phase 12\'s shape because this is phase 12\'s kind '
      'of dead: the INPUT source built twice with the identical '
      '`write(2, "PP-ENTERED\\n", 11)`, first in msg_puts_printf() -- %d of %d records, '
      '%d occurrences -- and then in msg_puts_display() -- %d of %d records, %d '
      'occurrences.  A prediction about a branch nothing takes has nothing but an '
      'instrument to confirm it, and a control is what says the instrument works'
      % (TAG, len(pp), n_rec, pp_n, len(ctl), n_rec, ctl_n))
print('  %-12s AND msg_use_printf() IS STILL ALIVE AFTER THE FOLD, measured on this '
      'phase\'s OWN output: TRUE %d times, every one at msg_clr_eos_force() and every '
      'one in %s -- one per mainerr row -- with `full_screen` FALSE %d of %d, so the '
      'body it guards is a no-op.  THIS IS PHASE 12\'S KIND OF DEAD AND NOT PHASE 9\'S: '
      'the branch CAN be taken and never is, so the evidence owed is an instrument at '
      'the site, a control, and probes -- not an argument that the code cannot run'
      % (TAG, tr_n, ' '.join(tr), tr_n - fs_n, tr_n))
PY

# tools/phaserun.sh runs tools/zerodelta.sh --phase 30 after this check, and that is the
# second opinion on the same claim -- against .reference/zero-baselines rather than
# against the binary this phase was handed.
