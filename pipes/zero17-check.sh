#!/bin/sh
# Zero phase 17, the check -- the deadly ladder that cannot run.
# See pipes/zero17-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero17-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero17-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# and `old`, that source built with the boundary's own flags.
#
# WHAT IS CLAIMED is that `deathtrap()`'s `entered >= 3` ladder -- `reset_signals()`,
# `_exit(8)` and `exit(7)` -- cannot be reached in any build of zero-vim, so removing
# it removes a POSSIBILITY and not a behaviour.  That is phase 13's kind of claim and
# it is argued the same way: an instrumented build of the source the phase was HANDED,
# with a control that must fire.
#
# THE INSTRUMENT is `write(2, "DTn\n", 4)` immediately after `++entered;` inside
# `deathtrap()`, plus `write(2, "DTLADDER\n", 9)` as the first statement INSIDE the
# ladder.  So every entry to the handler writes its depth and reaching the ladder says
# so, on stderr, from a signal handler, with one write(2) and no allocation.
#
# FIVE BUILDS, and the last two are what make this a measurement rather than a reading.
#
#   in_mark      the input, instrumented.  BOMBARDED: 8 concurrent sessions, each
#                sent 60 alternating SIGTERM/SIGHUP as fast as os.kill can issue
#                them.  Every session must reach the handler at least once, no
#                session may report DT3 or higher, and DTLADDER may not appear.
#   in_forced    in_mark plus a forced re-entry -- `raise(SIGHUP)` at the top of
#                `preserve_exit()` and `raise(SIGTERM)` at the top of the
#                `entered == 2` arm.  ONE signal, and it must report exactly DT1 and
#                DT2, no DTLADDER, and exit 1.  That is `entered` reaching its
#                maximum, deterministically.
#   in_nodefer3  in_forced with ONE FIELD CHANGED, `sa.sa_flags = SA_NODEFER`.  Same
#                forced re-entry, and now DT1 DT2 DT3 and DTLADDER, EXITING 7 --
#                which is `exit(7)`, the statement this phase deletes, running.
#   in_nodefer4  in_nodefer3 with one more forced signal at `entered == 3`.  DT4,
#                DTLADDER, EXITING 8 -- which is `_exit(8)`, the other statement this
#                phase deletes, running.
#   out_forced   THE OUTPUT with the identical instrument and the identical forced
#                re-entry.  DT1 and DT2, exit 1, and the SAME SCREEN as in_forced
#                drew: the forced double signal behaves the same with the ladder and
#                without it.
#
# The pair in_forced / in_nodefer3 is the whole argument in two binaries.  They differ
# in ONE `sigaction` field and nothing else, and the ladder runs in one and not the
# other -- so what makes it unreachable is the signal mask, and `signal_info[]`
# carrying exactly two `deadly = TRUE` rows.  A phase that removed the ladder because
# "reset_signals() makes it unreachable" would have the right answer for the wrong
# reason: `reset_signals()` is INSIDE the ladder and is never reached.
#
# AND THE ORDINARY DEADLY SIGNALS MUST NOT MOVE.  The uninstrumented pair -- the binary
# this phase was handed and the one it made -- is sent a single SIGTERM and a single
# SIGHUP, and each pair must agree on the exit status, on stderr and on WHAT THE EDITOR
# DREW: every snapshot, the final screen and the bell count, rebuilt from the escape
# stream by tools/zscreen.py, which is zero's own instrument.  The raw stream is NOT
# comparable and section 5 says why it is not.  `Vim: Caught deadly signal TERM`/`HUP`
# and `Vim: Finished.` are required to be on that screen, so the equality is not two
# blank screens agreeing.
#
# THE COUNTING TRAP, and it is why the symbol check is the load-bearing one.  `exit`
# has SIX mentions in the input and only two are calls: two string literals, a
# `goto exit;` and its `exit:` label inside `vim_regsub_both()`, `exit(7)` and
# `exit(r)`.  `assert exit at 0 mentions` FAILS on a correct phase, and `assert 'exit('
# at 0` fails on `mch_exit(`, `preserve_exit(` and `getout(`.  What is asserted here is
# `nm -u` -- the gone set is exactly `{_exit}` and `exit` is STILL undefined, being
# `mch_exit`'s and a later phase's -- plus `_exit` as a word, which is unambiguous
# because the label is `exit`.
set -eu

work=${1:?usage: zero17-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero17-check.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"
before_lines=$(cat "$state/input-lines")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")

# --- 1. the five instrumented sources -------------------------------------------------
mkdir -p "$tmp/i"
python3 - "$state/old.c" "$f" "$tmp/i" <<'PY'
import sys
TAG = 'deadly'
old, new, out = sys.argv[1], sys.argv[2], sys.argv[3]


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def edit(text, want, repl, what):
    if text.count(want) != 1:
        die('%s occurs %d times, expected 1 -- the instrument must land where it is '
            'meant to, or the zero it measures is a probe that cannot fail'
            % (what, text.count(want)))
    return text.replace(want, repl, 1)


# THE DEPTH MARKER, immediately after `++entered;`.  One write(2) of four bytes, which
# is all a signal handler may safely do.
ENTER = '    ++entered;\n\n    block_autocmds();\n'
MARK = ('    ++entered;\n'
        '\n'
        '    {\n'
        '        char dtbuf[4];\n'
        '        dtbuf[0] = \'D\';\n'
        '        dtbuf[1] = \'T\';\n'
        '        dtbuf[2] = (char)(\'0\' + (entered > 9 ? 9 : entered));\n'
        '        dtbuf[3] = \'\\n\';\n'
        '        (void)write(2, dtbuf, 4);\n'
        '    }\n'
        '\n'
        '    block_autocmds();\n')

# THE LADDER MARKER, the first statement inside the block this phase deletes.  It
# exists only in the input; the output has no ladder to mark.
LADDER = ('    if (entered >= 3)\n'
          '    {\n'
          '        reset_signals();\n')
LADDER_MARK = ('    if (entered >= 3)\n'
               '    {\n'
               '        (void)write(2, "DTLADDER\\n", 9);\n'
               '        reset_signals();\n')

# THE FORCED RE-ENTRY.  `preserve_exit()` is where the handler ends up at entered == 1
# and the `entered == 2` arm is where it ends up at 2, so a raise in each is a
# deterministic way of driving `entered` as high as the signal mask will let it go.
PRESERVE = 'preserve_exit(void)\n{\n\n    prepare_to_exit();\n'
PRESERVE_RAISE = ('preserve_exit(void)\n{\n\n    raise(SIGHUP);\n\n'
                  '    prepare_to_exit();\n')
DOUBLE = ('    if (entered == 2)\n'
          '    {\n'
          '         out_str((char_u *)("Vim: Double signal, exiting\\n")) ;\n')
DOUBLE_RAISE = ('    if (entered == 2)\n'
                '    {\n'
                '        raise(SIGTERM);\n'
                '         out_str((char_u *)("Vim: Double signal, exiting\\n")) ;\n')

# ONE FIELD, and it is the whole difference between a ladder that cannot run and one
# that does.
FLAGS = '            sa.sa_flags = 0;\n'
FLAGS_NODEFER = '            sa.sa_flags = SA_NODEFER;\n'

# AND ONE MORE FORCED SIGNAL, at entered == 3, to reach the `_exit(8)` arm.
BEFORE_LADDER = '    full_screen = FALSE;\n    if (entered >= 3)\n'
BEFORE_LADDER_RAISE = ('    full_screen = FALSE;\n'
                       '    if (entered == 3)\n'
                       '    {\n'
                       '        raise(SIGHUP);\n'
                       '    }\n'
                       '    if (entered >= 3)\n')

t = open(old, errors='surrogateescape').read()
in_mark = edit(edit(t, ENTER, MARK, 'the `++entered;` the depth marker follows'),
               LADDER, LADDER_MARK, 'the ladder the second marker opens')
in_forced = edit(edit(in_mark, PRESERVE, PRESERVE_RAISE, "preserve_exit()'s head"),
                 DOUBLE, DOUBLE_RAISE, "the `entered == 2` arm")
in_nodefer3 = edit(in_forced, FLAGS, FLAGS_NODEFER, "catch_signals()'s `sa_flags = 0`")
in_nodefer4 = edit(in_nodefer3, BEFORE_LADDER, BEFORE_LADDER_RAISE,
                   'the statement before the ladder')

n = open(new, errors='surrogateescape').read()
if LADDER in n:
    die('the ladder is still in the output')
out_forced = edit(edit(edit(n, ENTER, MARK, 'the `++entered;` in the OUTPUT'),
                       PRESERVE, PRESERVE_RAISE, "preserve_exit()'s head in the OUTPUT"),
                  DOUBLE, DOUBLE_RAISE, 'the `entered == 2` arm in the OUTPUT')

for name, text in (('in_mark', in_mark), ('in_forced', in_forced),
                   ('in_nodefer3', in_nodefer3), ('in_nodefer4', in_nodefer4),
                   ('out_forced', out_forced)):
    open('%s/%s.c' % (out, name), 'w', errors='surrogateescape').write(text)
print('  %-12s five instrumented sources: the input marked, the input marked and '
      'forced, the same with ONE FIELD changed to SA_NODEFER, the same again forced '
      'one step further, and the OUTPUT marked and forced identically' % TAG)
PY

for n in in_mark in_forced in_nodefer3 in_nodefer4 out_forced; do
    # shellcheck disable=SC2086
    ( gcc $cflags $ldflags -o "$tmp/i/$n" "$tmp/i/$n.c" ) &
done

# --- 2. the source, while the five compile --------------------------------------------
python3 - "$f" "$state/old.c" <<'PY'
import re, sys
TAG = 'deadly'
new = open(sys.argv[1], errors='surrogateescape').read()
old = open(sys.argv[2], errors='surrogateescape').read()
fail = []


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


LADDER = ('    if (entered >= 3)\n'
          '    {\n'
          '        reset_signals();\n'
          '        if (entered >= 4)\n'
          '        {\n'
          '            _exit(8);\n'
          '        }\n'
          '        exit(7);\n'
          '    }\n')
if old.count(LADDER) != 1:
    fail.append('the input did not hold exactly one `entered >= 3` ladder, so this is '
                'not the file the phase was written against')
if LADDER in new:
    fail.append('the ladder survives in the output')

# THE COUNTING TRAP.  `exit` is a word this file uses for four things that are not a
# call, so both sides are counted and the DIFFERENCE is what is asserted.
if mentions(old, 'exit') != 6 or mentions(new, 'exit') != 5:
    fail.append('`exit` as a word is %d in the input and %d in the output, expected 6 '
                'and 5 -- two string literals, a `goto exit;`, its `exit:` label in '
                'vim_regsub_both(), `exit(7)` and `exit(r)`, of which only `exit(7)` '
                'goes' % (mentions(old, 'exit'), mentions(new, 'exit')))
if mentions(old, '_exit') != 1 or mentions(new, '_exit') != 0:
    fail.append('`_exit` is %d in the input and %d in the output, expected 1 and 0'
                % (mentions(old, '_exit'), mentions(new, '_exit')))
calls_old = re.findall(r'^\s*exit\(', old, re.M)
calls_new = re.findall(r'^\s*exit\(', new, re.M)
if len(calls_old) != 2 or len(calls_new) != 1:
    fail.append('%d statements begin with `exit(` in the input and %d in the output, '
                "expected 2 and 1 -- mch_exit's `exit(r);` is the one that is left, "
                'and it is a later phase\'s' % (len(calls_old), len(calls_new)))
if '    exit(r);\n' not in new:
    fail.append("mch_exit's `exit(r);` went, and it is not this phase's")

# THE TWO FACTS THE UNREACHABILITY RESTS ON, asserted on the OUTPUT so that a later
# phase cannot make them false without this check saying so.
for s in ('SIGSEGV', 'SIGBUS', 'SIGILL', 'SIGFPE', 'SIGABRT', 'SIGQUIT', 'SIGTRAP',
          'SIGSYS'):
    if mentions(new, s):
        fail.append('%s is named in the output, and the ladder was unreachable only '
                    'because SIGHUP and SIGTERM are the ONLY deadly signals' % s)
TABLE = ('} signal_info[] =\n'
         '{\n'
         '    {SIGHUP,        "HUP",      TRUE},\n'
         '    {SIGTERM,       "TERM",     TRUE},\n'
         '    {SIGINT,        "INT",      FALSE},\n'
         '    {SIGWINCH,      "WINCH",    FALSE},\n'
         '    {SIGTSTP,       "TSTP",     FALSE},\n'
         '    {-1,            "Unknown!", FALSE}\n'
         '};\n')
if new.count(TABLE) != 1:
    fail.append('signal_info[] is not the five rows this phase was written against, of '
                'which EXACTLY TWO are deadly -- a third `TRUE` row would let `entered` '
                'reach 3')
INSTALL = ('        if (signal_info[i].deadly)\n'
           '        {\n'
           '            struct sigaction sa;\n'
           '\n'
           '            sa.sa_handler = func_deadly;\n'
           '            sigemptyset(&sa.sa_mask);\n'
           '            sa.sa_flags = 0;\n'
           '            sigaction(signal_info[i].sig, &sa, NULL);\n'
           '        }\n')
if new.count(INSTALL) != 1:
    fail.append("catch_signals()'s deadly arm is not the `sigemptyset(&sa.sa_mask)` "
                'plus `sa.sa_flags = 0` this phase was written against, and that one '
                'field is the whole reason a deadly signal cannot interrupt its own '
                'handler')
for flag in ('SA_NODEFER', 'SA_RESETHAND', 'siginterrupt'):
    if mentions(new, flag):
        fail.append('%s is named in the output, and it is exactly what would make the '
                    'ladder reachable' % flag)
if mentions(new, 'deathtrap') != 3:
    fail.append('deathtrap has %d mentions, expected 3 -- a prototype, a definition and '
                'the one `catch_signals(deathtrap, SIG_ERR)`.  A fourth would be an '
                'ordinary call, which no signal mask protects against'
                % mentions(new, 'deathtrap'))

# NOTHING IS ORPHANED, and reset_signals() is the one that looks as though it should
# be: the ladder held one of its four mentions and mainerr() holds another.
if mentions(new, 'reset_signals') != 3:
    fail.append('reset_signals has %d mentions, expected 3 -- a prototype, its '
                "definition and mainerr()'s call.  The ladder held the fourth, and "
                'mainerr() is why the function is NOT orphaned by this cut'
                % mentions(new, 'reset_signals'))
if mentions(new, 'catch_signals') != 4:
    fail.append('catch_signals has %d mentions, expected 4' % mentions(new, 'catch_signals'))
for name, want in (('getout', 7), ('preserve_exit', 3), ('mch_exit', 8),
                   ('vim_handle_signal', 5), ('set_signals', 3)):
    if mentions(new, name) != want:
        fail.append('%s has %d mentions, expected %d -- this phase touches nothing but '
                    'the nine lines of the ladder' % (name, mentions(new, name), want))

# NINE LINES AND NOT ONE MORE, which is also what says the sweep found nothing.
if len(new.split('\n')) != len(old.split('\n')) - 9:
    fail.append('the file lost %d lines, expected 9'
                % (len(old.split('\n')) - len(new.split('\n'))))
if runs(new) != runs(old):
    fail.append('runs of two blank lines: %d in the output against %d in the input'
                % (runs(new), runs(old)))

# The tables this phase does not touch, and the directive count phase 16 left.
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
                'phase 16 left')
if re.search(r'\bFILE\b', new):
    fail.append('FILE is named in zero-vim.c, and phase 13 took it to zero')

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s the nine lines are gone and nothing else is: `_exit` 1 -> 0, `exit` as '
      'a word 6 -> 5 with EXACTLY ONE call left -- mch_exit\'s `exit(r);`, which is a '
      'later phase\'s -- and reset_signals 4 -> 3, still called by mainerr() and so NOT '
      'orphaned' % TAG)
print('  %-12s the two facts the unreachability rests on, asserted on the OUTPUT so a '
      'later phase cannot quietly falsify them: signal_info[] is five rows with '
      'EXACTLY TWO deadly, no SIGSEGV/SIGBUS/SIGILL/SIGFPE anywhere, and '
      "catch_signals()'s deadly arm still installs with `sa.sa_flags = 0` and an empty "
      'sa_mask, SA_NODEFER named nowhere' % '')
print('  %-12s deathtrap at three mentions -- a prototype, a definition and the one '
      'installation -- so a signal is the only way in; and cmdnames[] 98, options[] '
      '108, twelve `#include`s, FILE at 0, none of which this phase touches' % '')

# THE COUNTING TRAP, said out loud, because the next reader will reach for it.
print('  %-12s the counting trap: `exit` is FIVE mentions in the output and only one '
      'is a call -- two string literals and a `goto exit;` with its `exit:` label in '
      'vim_regsub_both() are the others -- so `assert exit at 0` fails on a correct '
      "phase and `assert 'exit(' at 0` fails on mch_exit(, preserve_exit( and getout(. "
      'The assertion that works is nm -u, in section 3' % '')
PY

# --- 3. the compile, the linkage and the libc surface ---------------------------------
# `_exit` AND NOTHING ELSE.  Stated as the two comm sets rather than as a count, and
# `exit` is required to be STILL undefined: it is mch_exit's and a later phase's.
cp "$state/symbols/undefined" "$tmp/before.u"
tools/phasecheck.sh "$work" "$f" "$state/symbols"
comm -23 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/gone.u"
comm -13 "$tmp/before.u" .cache/symbols/last/undefined > "$tmp/came.u"
printf '_exit\n' > "$tmp/want.u"
if ! cmp -s "$tmp/gone.u" "$tmp/want.u" || [ -s "$tmp/came.u" ]; then
    echo "  deadly       the libc surface did not move by exactly _exit:"
    echo "               gone: $(tr '\n' ' ' < "$tmp/gone.u")"
    echo "               came: $(tr '\n' ' ' < "$tmp/came.u")"
    exit 1
fi
grep -qx exit .cache/symbols/last/undefined \
    || { echo "  deadly       exit went too, and it is not this phase's: mch_exit's exit(r) is the core's one remaining way to end the process, and demoting it is a later phase's"; exit 1; }
# ZERO-PLAN.md 4b's invariant, re-asserted for free.
for absent in open creat openat stat access fcntl getcwd strerror fopen fdopen \
              opendir fclose getc putc fsync; do
    if grep -qx "$absent" .cache/symbols/last/undefined; then
        echo "  deadly       $absent is undefined, and the core has had no way to open a file since phase 13"; exit 1
    fi
done
echo "  deadly       symbols $(cat .cache/symbols/last/before) -> $(cat .cache/symbols/last/after), the gone set is EXACTLY _exit and nothing arrives -- 'exit' is still undefined, being mch_exit's and a later phase's, and the WORD 'exit' is useless as a source assertion because two string literals and a goto label carry it"

# --- 4. the binary --------------------------------------------------------------------
make -C "$work" clean >/dev/null 2>&1 || true
[ -e "$work/zero-vim" ] && { echo "  build        the clean did not remove zero-vim"; exit 1; }
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$bin") bytes"

# --- 5. the five instrumented binaries, which are the whole of this phase's evidence ---
wait || true
for n in in_mark in_forced in_nodefer3 in_nodefer4 out_forced; do
    [ -x "$tmp/i/$n" ] || { echo "  deadly       the instrumented build $n did not compile"; exit 1; }
done

python3 - "$tmp/i" "$state/old" "$bin" <<'PY'
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
import zscreen
import zstream

TAG = 'deadly'
d, old_bin, new_bin = sys.argv[1], sys.argv[2], sys.argv[3]
fail = []


def session(binary, sigs):
    """Start the editor on pipes, type into it, then send it signals.

    argv[0] decides the mode (CLAUDE.md), so the binary is staged as `vim`; the
    environment is emptied the way every harness here empties it; and the child gets
    a session of its own, because :suspend's lesson is that a signal sent to a
    process group reaches the harness too.  It waits for the editor to go quiet before
    it signals, so that what was drawn is a property of the editor and not of the
    machine's load -- see the loop below.
    """
    vim = zstream.stage(binary)     # argv[0], and the copy race: tools/zstream.py
    home = tempfile.mkdtemp(prefix='zero17-home-')
    env = dict(os.environ)
    env.update(TERM='xterm', HOME=home, VIM=os.path.join(home, 'novim'),
               VIMRUNTIME=os.path.join(home, 'novim'),
               XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    p = subprocess.Popen([vim, '+set paste'], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env,
                         start_new_session=True)
    try:
        p.stdin.write(b'ihello')
        p.stdin.flush()
    except OSError:
        pass
    # SETTLE BEFORE SIGNALLING, AND ON CONTENT RATHER THAN ON A CLOCK.  A fixed sleep
    # signals the editor wherever its redraw happened to have got to, and with sixteen
    # of these running at once that is a recording of the machine's load: measured, the
    # in_forced / out_forced streams came back 2,136 bytes each and DIFFERENT under a
    # concurrent run and identical when run alone, and a quiet-for-300ms drain was still
    # wrong once, on a startup that took longer than that to produce its first byte.
    # So the wait is for the editor to have DRAWN THE TYPED TEXT and then gone quiet,
    # and a run that never gets there is reported rather than compared.  The content
    # half is what a clock alone cannot give: the quiet is only ever asked about after
    # `hello` is on the screen.
    drawn = b''
    last, deadline = time.time(), time.time() + 20.0
    while True:
        if time.time() > deadline:
            drawn += b'\n<<EDITOR NEVER DREW THE TYPED TEXT>>'
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
    for s in sigs:
        try:
            os.kill(p.pid, s)
        except ProcessLookupError:
            break
    try:
        out, err = p.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        p.kill()
        out, err = p.communicate()
    shutil.rmtree(home, ignore_errors=True)
    return p.returncode, drawn + out, err


def marks(err):
    """The depths the handler reported, and whether the ladder was entered."""
    seen = [int(l[2]) for l in err.decode('latin-1').split('\n')
            if len(l) == 3 and l.startswith('DT') and l[2].isdigit()]
    return seen, b'DTLADDER' in err


TERM, HUP = signal.SIGTERM, signal.SIGHUP
BOMB = [TERM if i % 2 == 0 else HUP for i in range(60)]
JOBS = ([('bomb%d' % i, os.path.join(d, 'in_mark'), BOMB) for i in range(8)]
        + [('in_forced', os.path.join(d, 'in_forced'), [TERM]),
           ('in_nodefer3', os.path.join(d, 'in_nodefer3'), [TERM]),
           ('in_nodefer4', os.path.join(d, 'in_nodefer4'), [TERM]),
           ('out_forced', os.path.join(d, 'out_forced'), [TERM])]
        + [('old_term', old_bin, [TERM]), ('new_term', new_bin, [TERM]),
           ('old_hup', old_bin, [HUP]), ('new_hup', new_bin, [HUP])])
with concurrent.futures.ThreadPoolExecutor(max_workers=len(JOBS)) as ex:
    res = dict(zip([j[0] for j in JOBS],
                   ex.map(lambda j: session(j[1], j[2]), JOBS)))

stuck = [n for n, (rc, out, err) in res.items() if b'NEVER DREW' in out]
if stuck:
    print('  %-12s %s did not draw the typed text within fifteen seconds, so nothing '
          'below is a measurement of the editor' % (TAG, ', '.join(sorted(stuck))))
    sys.exit(1)

# ---- the bombardment: the maximum `entered` ever observed is 2 ------------------------
# The assertion is one-sided, so machine load can only ever make it weaker, never make
# it fail spuriously -- but a session that never reached the handler at all would make
# the zero meaningless, so every one is required to have reported a depth.
high, twos, silent = 0, 0, []
for i in range(8):
    rc, out, err = res['bomb%d' % i]
    seen, ladder = marks(err)
    if not seen:
        silent.append('bomb%d' % i)
    high = max([high] + seen)
    twos += 1 if max(seen or [0]) >= 2 else 0
    if ladder:
        fail.append('bomb%d reached the `entered >= 3` ladder, so this phase removes '
                    'code that CAN run and the cut is wrong' % i)
if silent:
    fail.append('%s never entered deathtrap() at all, so the maximum below is a '
                'measurement of nothing' % ', '.join(silent))
if high > 2:
    fail.append('the bombardment drove `entered` to %d, and two deadly signals each '
                'blocked inside their own handler cannot do that' % high)

# ---- the forced pair, which is the argument -------------------------------------------
want = [
    # name, the depths required, ladder?, exit status, why
    ('in_forced', [1, 2], False, 1,
     'the input, forced: `entered` reaches its maximum of 2, the `Vim: Double signal, '
     'exiting` arm runs and calls getout(1)'),
    ('in_nodefer3', [1, 2, 3], True, 7,
     'the SAME source with ONE FIELD changed to SA_NODEFER: the ladder runs and '
     'exit(7) ends the process'),
    ('in_nodefer4', [1, 2, 3, 4], True, 8,
     'and one forced signal further: _exit(8) ends it'),
    ('out_forced', [1, 2], False, 1,
     'THE OUTPUT, instrumented and forced identically: the same two depths and the '
     'same exit'),
]
for name, depths, ladder, rc_want, why in want:
    rc, out, err = res[name]
    seen, got_ladder = marks(err)
    if seen != depths:
        fail.append('%s reported depths %s, expected %s -- %s'
                    % (name, seen or 'none', depths, why))
    if got_ladder != ladder:
        fail.append('%s %s the ladder and it must %s -- %s'
                    % (name, 'entered' if got_ladder else 'did not enter',
                       'enter it' if ladder else 'not', why))
    if rc != rc_want:
        fail.append('%s exited %s, expected %d -- %s' % (name, rc, rc_want, why))
# ---- what two runs are compared BY, and it is the screen and not the stream -----------
# THE RAW BYTE STREAM IS NOT COMPARABLE HERE, and that is a measurement rather than a
# caution.  The editor emits `\x1b[?4m` -- a private mode that changes nothing on the
# screen -- at a point that depends on when its own flush happened, so two runs of ONE
# binary can differ by where in the stream those five bytes sit: measured, in_forced and
# out_forced came back 2,136 bytes each, byte-for-byte equal in three runs out of six and
# differing at offset 2,003 in the other three, the whole difference being `\x1b[?4m`
# before `\x1b[?25l` rather than after `\x1b[?25h`.  The plain pair flaked the same way.
# So the comparison is what the editor DREW -- zero's own instrument, tools/zscreen.py:
# every snapshot, the final screen and the bell count, none of which a private mode
# touches -- beside the exit status and stderr, which are bytes and are compared as such.
def picture(rec):
    rc, out, err = rec
    scr = zscreen.Screen(24, 80)
    scr.feed(out)
    return rc, tuple(scr.snaps), scr.dump(), scr.bells, err


if picture(res['in_forced']) != picture(res['out_forced']):
    fail.append('the forced double signal draws a different screen with the ladder and '
                'without it.  The ladder is not on that path, so it must not be')

# ---- and the ordinary deadly signals, which must not move ------------------------------
for sig, tag in (('term', 'TERM'), ('hup', 'HUP')):
    old_p = picture(res['old_%s' % sig])
    new_p = picture(res['new_%s' % sig])
    for what in ('Vim: Caught deadly signal %s' % tag, 'Vim: Finished.'):
        if what not in old_p[2]:
            fail.append('a single SIG%s did not make the binary this phase was handed '
                        'draw %r, so the comparison below would agree for the wrong '
                        'reason' % (tag, what))
    if old_p != new_p:
        where = [n for n, o, w in zip(('exit', 'snapshots', 'final screen', 'bells',
                                       'stderr'), old_p, new_p) if o != w]
        fail.append('a single SIG%s moved, in the %s: %s -> %s.  This phase removes a '
                    'branch neither signal can reach'
                    % (tag, ' and the '.join(where), old_p[0], new_p[0]))

if fail:
    for line in fail:
        print('  %-12s %s' % (TAG, line))
    sys.exit(1)
print('  %-12s BOMBARDED: eight concurrent sessions, 60 alternating SIGTERM/SIGHUP '
      'each at full speed, every one of them reaching deathtrap() and %d of the eight '
      'reaching it twice.  The maximum `entered` ever observed is %d, and DTLADDER '
      'never appears' % (TAG, twos, high))
print('  %-12s FORCED, and this is the argument in two binaries.  in_forced and '
      'in_nodefer3 are the same source differing in ONE `sigaction` FIELD: with '
      '`sa_flags = 0` the forced double signal stops at depth 2 and exits 1, and with '
      '`SA_NODEFER` it reaches depth 3, enters the ladder and EXITS 7 -- which is '
      'exit(7) running.  One forced signal further and it exits 8, which is _exit(8) '
      'running' % '')
print('  %-12s so the ladder is not dead code that happens to be dead: it is '
      'unreachable BECAUSE each deadly signal is blocked inside its own handler and '
      "BECAUSE there are only two of them.  `reset_signals()` is INSIDE the ladder and "
      'has nothing to do with it' % '')
print('  %-12s the output instrumented and forced identically stops at depth 2 and '
      'DRAWS THE SAME SCREEN as the input did, and a single SIGTERM and a single '
      'SIGHUP give the binary this phase was handed and the one it made the same exit '
      'status, the same stderr and the same snapshots, final screen and bell count -- '
      'with `Vim: Caught deadly signal` and `Vim: Finished.` required to be ON that '
      'screen, so the equality is not two blank screens agreeing.  The comparison is '
      'the screen and not the stream because the stream is not comparable: the editor '
      'emits `\\x1b[?4m`, which draws nothing, at a point that depends on its own '
      'flush, and two runs of ONE binary differ there' % '')
PY

# tools/phaserun.sh runs tools/zerodelta.sh --phase 17 after this check, and this
# phase declares NOTHING: the corpus must not move at all.
