#!/bin/sh
# Zero phase 17 -- the deadly ladder that cannot run.  See ZERO-GOAL.md.
#
# Usage: pipes/zero17-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# `deathtrap()` is the handler for the deadly signals, and it opens with a ladder that
# counts how many times it has been entered:
#
#     if (entered >= 3)
#     {
#         reset_signals();
#         if (entered >= 4)
#         {
#             _exit(8);
#         }
#         exit(7);
#     }
#
# NOTHING IN ANY BUILD OF zero-vim CAN MAKE `entered` REACH 3, and that is the whole
# phase.  It is phase 13's kind of cut -- the POSSIBILITY has never existed -- rather
# than phase 9's, where an earlier zero phase made a live path unreachable.  What makes
# it impossible is two facts about this file, and neither is zero's doing:
#
#   * `catch_signals()` installs the deadly handler with `sa.sa_flags = 0` and
#     `sigemptyset(&sa.sa_mask)`.  NO `SA_NODEFER`, so the signal being handled is
#     blocked for the duration of its own handler.  That is the whole mechanism, and
#     it is asserted below character for character.
#   * `signal_info[]` has exactly TWO rows carrying `deadly = TRUE`, `SIGHUP` and
#     `SIGTERM`.  SIGSEGV, SIGBUS, SIGILL and SIGFPE are at ZERO mentions in this file
#     -- whim removed all four -- so there is no third deadly signal to arrive.
#
# Two deadly signals, each blocked inside its own handler, means `entered` can reach 2
# -- TERM nested inside HUP's handler, or the reverse, which is the
# `Vim: Double signal, exiting` arm, and that arm calls `getout(1)` and never returns.
# It cannot reach 3: by then both are blocked and nothing else is caught.
#
# THE REASON MATTERS AND THE WRONG REASON IS AVAILABLE.  A phase that removed the
# ladder because "reset_signals() makes it unreachable" would have the right answer for
# the wrong reason -- `reset_signals()` is INSIDE the ladder and is never reached -- and
# would be wrong on any tree with three deadly signals.  The argument is the signal
# mask and the two-row table, and pipes/zero17-check.sh measures exactly that: the same
# source with ONE FIELD CHANGED, `sa.sa_flags = SA_NODEFER`, reaches the ladder and
# exits 7, and with one more forced signal exits 8.
#
# THE COUNTING TRAP, stated here because the obvious assertion fails on a correct
# phase.  `\bexit\b` has SIX mentions in the input and only two of them are calls:
#
#     46925  "Type  :qa!  and press <Enter> to abandon all changes and exit Vim"
#     46945  "Type  :qa  and press <Enter> to exit Vim"          two string literals
#     55908          exit(7);                                    this phase's
#     56170      exit(r);                                        mch_exit's, and the
#                                                                only one that runs
#     58180                          goto exit;                  a LABEL, inside
#     58251  exit:                                               vim_regsub_both()
#
# So `assert exit at 0 mentions` fails on a correct phase, and `assert 'exit(' at 0`
# fails on `mch_exit(`, `preserve_exit(`, `prepare_to_exit(`, `read_error_exit(` and
# `getout(`.  What this edit asserts instead is every one of the six BY ITS OWN EXACT
# LINE, and what the check asserts is `nm -u`, which cannot be confused by a label.
#
# THE INPUT SOURCE AND ITS BINARY ARE KEPT, because every probe this phase has is a
# build of the source it was HANDED: the ladder is not in the output, so the only place
# it can be shown to be dead -- and shown to be live under `SA_NODEFER` -- is the input.
set -eu

work=${1:?usage: zero17-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero17-edit.sh <work-dir> <state-dir>}
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
TAG = 'deadly'
import re, sys
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()


def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))


def say(what):
    print('  %-12s %s' % (TAG, what))


def mentions(text, name):
    return len(re.findall(r'\b%s\b' % name, text))


def blank_runs(text):
    L = text.split('\n')
    return sum(1 for i in range(1, len(L)) if L[i] == '' and L[i - 1] == '')


def once(text, what, why):
    if t.count(text) != 1:
        die('%s occurs %d times, expected 1 -- %s' % (what, t.count(text), why))


# ---- 1. there is no third deadly signal, and there never was ------------------------
# whim removed the four crash signals, so this is not a statement about what zero did;
# it is the fact zero inherited, and it is the half of the argument a reader is most
# likely to assume rather than check.
CRASH = ('SIGSEGV', 'SIGBUS', 'SIGILL', 'SIGFPE', 'SIGABRT', 'SIGQUIT', 'SIGTRAP',
         'SIGSYS')
live = [s for s in CRASH if mentions(t, s)]
if live:
    die('this file names %s -- the ladder below is unreachable only because the ONLY '
        'deadly signals are SIGHUP and SIGTERM, so a third one makes the whole '
        'argument false' % ', '.join('%s (%d)' % (s, mentions(t, s)) for s in live))

# The table itself, character for character.  EXACTLY TWO ROWS ARE DEADLY, and the
# count is the statement: a third `TRUE` row would let `entered` reach 3.
TABLE = ('} signal_info[] =\n'
         '{\n'
         '    {SIGHUP,        "HUP",      TRUE},\n'
         '    {SIGTERM,       "TERM",     TRUE},\n'
         '    {SIGINT,        "INT",      FALSE},\n'
         '    {SIGWINCH,      "WINCH",    FALSE},\n'
         '    {SIGTSTP,       "TSTP",     FALSE},\n'
         '    {-1,            "Unknown!", FALSE}\n'
         '};\n')
once(TABLE, 'signal_info[] as this phase was written against',
     'the two-row deadly table IS the argument and it is asserted as text')
say('SIGSEGV, SIGBUS, SIGILL and SIGFPE at ZERO mentions -- whim removed all four -- '
    'and signal_info[] is the five rows this phase was written against, of which '
    'EXACTLY TWO are deadly: SIGHUP and SIGTERM')

# ---- 2. each deadly signal is blocked inside its own handler ------------------------
# This is the other half, and it is one field.  `sa_flags = 0` with an empty `sa_mask`
# is the default: the signal being delivered is added to the mask for the duration of
# the handler.  SA_NODEFER is what would turn that off, and it is named NOWHERE.
INSTALL = ('        if (signal_info[i].deadly)\n'
           '        {\n'
           '            struct sigaction sa;\n'
           '\n'
           '            sa.sa_handler = func_deadly;\n'
           '            sigemptyset(&sa.sa_mask);\n'
           '            sa.sa_flags = 0;\n'
           '            sigaction(signal_info[i].sig, &sa, NULL);\n'
           '        }\n')
once(INSTALL, "catch_signals()'s deadly arm",
     'the `sa_flags = 0` in it is the whole reason the ladder cannot be reached')
for flag in ('SA_NODEFER', 'SA_RESETHAND', 'SA_ONSTACK', 'siginterrupt'):
    if mentions(t, flag):
        die('%s is named in this file, and it is exactly what would let a deadly '
            'signal interrupt its own handler' % flag)
say("catch_signals()'s deadly arm installs with `sigemptyset(&sa.sa_mask)` and "
    '`sa.sa_flags = 0`, and SA_NODEFER, SA_RESETHAND and siginterrupt are named '
    'NOWHERE in the file -- so each deadly signal is blocked for the duration of its '
    'own handler, and with only two of them `entered` can reach 2 and no further')

# ---- 3. nothing but the kernel can enter deathtrap ----------------------------------
# `entered` is a function-scope `static int` and the ONLY thing that increments it is
# an entry to the handler.  If deathtrap() were called as an ordinary function from
# anywhere, the mask argument above would say nothing.
if mentions(t, 'deathtrap') != 3:
    die('deathtrap has %d mentions, expected 3 -- its prototype, its definition and '
        'the one `catch_signals(deathtrap, SIG_ERR)` that installs it.  A fourth '
        'would be an ordinary call, which no signal mask protects against'
        % mentions(t, 'deathtrap'))
once('    catch_signals(deathtrap, SIG_ERR);\n', 'the one installation of deathtrap',
     'it is the only way the handler is reached')
HEAD = ('deathtrap  (int sigarg  __attribute__((unused)) ) \n'
        '{\n'
        '    static int  entered = 0;\n')
once(HEAD, "deathtrap()'s head", '`entered` is a function-scope static starting at 0')
body = t[t.index(HEAD):]
body = body[:body.index('\n}\n') + 3]
writes = [re.sub(r'\s+', '', w) for w in
          re.findall(r'\+\+entered|entered\+\+|--entered|entered--|entered\s*=(?!=)', body)]
if sorted(writes) != ['++entered', 'entered=']:
    die('`entered` is written in deathtrap() as %s, expected only its initialiser and '
        'one `++entered` -- any other write would make the ladder reachable by '
        'arithmetic rather than by a signal' % ', '.join(sorted(writes)))
say('deathtrap at THREE mentions -- a prototype, a definition and the one '
    '`catch_signals(deathtrap, SIG_ERR)` -- and inside it `entered` is written by its '
    'initialiser and by one `++entered` and by nothing else, so the only way to raise '
    'it is to deliver a deadly signal')

# ---- 4. the counting trap, and the six mentions one by one --------------------------
# `\bexit\b` is six, and only two are calls.  Asserting them by line is what keeps a
# later reader from writing `assert exit at 0`, which fails on a correct phase.
SIX = [
    ('                char *ms = _("Type  :qa!  and press <Enter> to abandon all '
     'changes and exit Vim");\n', 'a string literal'),
    ('                    msg(_("Type  :qa  and press <Enter> to exit Vim"));\n',
     'a string literal'),
    ('        exit(7);\n', "the ladder's, which this phase removes"),
    ('    exit(r);\n', "mch_exit's -- the only exit() that has ever run"),
    ('                        goto exit;\n', 'a GOTO, in vim_regsub_both()'),
    ('exit:\n', 'a LABEL, in vim_regsub_both()'),
]
for text, why in SIX:
    once(text, '`%s`' % text.strip(), why)
if mentions(t, 'exit') != 6:
    die('`exit` as a word has %d mentions, expected the 6 named above' % mentions(t, 'exit'))
if mentions(t, '_exit') != 1:
    die('`_exit` has %d mentions, expected 1 -- the `_exit(8)` inside the ladder'
        % mentions(t, '_exit'))
once('            _exit(8);\n', '`_exit(8)`', 'it is the ladder\'s inner arm')
calls = re.findall(r'^\s*exit\(', t, re.M)
if len(calls) != 2:
    die('%d statements begin with `exit(`, expected 2 -- `exit(7)` and `exit(r)`'
        % len(calls))
say('the counting trap: `exit` is SIX mentions and only TWO are calls -- two string '
    'literals, a `goto exit;` and its `exit:` label in vim_regsub_both(), and '
    '`exit(7)` and `exit(r)`.  `_exit` is one, and it is unambiguous')

# ---- 5. what is around the ladder, for the sweep ------------------------------------
BEFORE = {'reset_signals': 4,    # prototype, the ladder's call, definition, mainerr's
          'catch_signals': 4,    # prototype, set_signals', reset_signals', definition
          'getout': 7, 'preserve_exit': 3, 'mch_exit': 8}
for name, want in sorted(BEFORE.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions, expected %d -- the anchors were counted against a '
            'different file' % (name, k, want))
say('reset_signals 4 and catch_signals 4 going in, with getout 7, preserve_exit 3 and '
    'mch_exit 8 -- none of which this phase touches')

# ---- 6. the cut: nine lines, and nothing else ---------------------------------------
runs_before = blank_runs(t)
lines_before = len(t.split('\n'))
LADDER = ('    if (entered >= 3)\n'
          '    {\n'
          '        reset_signals();\n'
          '        if (entered >= 4)\n'
          '        {\n'
          '            _exit(8);\n'
          '        }\n'
          '        exit(7);\n'
          '    }\n')
once(LADDER, 'the ladder', 'it is deleted as exact text and there is one of it')
# It sits between `full_screen = FALSE;` and the `entered == 2` arm with no blank line
# either side, so nine lines go and the paragraphing does not move.
CONTEXT = '    full_screen = FALSE;\n' + LADDER + '    if (entered == 2)\n'
once(CONTEXT, 'the ladder in its context',
     'deleting it must leave `full_screen = FALSE;` next to the `entered == 2` arm')
t = t.replace(LADDER, '', 1)
say('the nine lines go, and with them the only `_exit` in the file and one of its two '
    '`exit()` calls')

# ---- 7. what the file is now --------------------------------------------------------
if mentions(t, '_exit'):
    die('_exit survives the cut')
if mentions(t, 'exit') != 5:
    die('`exit` as a word has %d mentions after the cut, expected 5' % mentions(t, 'exit'))
if len(re.findall(r'^\s*exit\(', t, re.M)) != 1:
    die('%d statements begin with `exit(` after the cut, expected exactly one -- '
        "mch_exit's `exit(r);`" % len(re.findall(r'^\s*exit\(', t, re.M)))
AFTER = {'reset_signals': 3,     # the ladder's call went; mainerr still calls it
         'catch_signals': 4}
for name, want in sorted(AFTER.items()):
    k = mentions(t, name)
    if k != want:
        die('%s has %d mentions after the cut, expected %d' % (name, k, want))
once('    reset_signals();\n', 'the one remaining `reset_signals();` call',
     "it is mainerr's, and it is why the function is NOT orphaned by this cut")
if blank_runs(t) != runs_before:
    die('the cut left %d runs of two blank lines where there were %d'
        % (blank_runs(t), runs_before))
if len(t.split('\n')) != lines_before - 9:
    die('the file lost %d lines, expected 9'
        % (lines_before - len(t.split('\n'))))
say('_exit at 0, `exit` at 5 mentions with exactly ONE call left -- mch_exit\'s -- '
    'reset_signals at 3, still called by mainerr() and so NOT orphaned, catch_signals '
    'unchanged at 4, and %d runs of two blank lines, exactly as before' % blank_runs(t))

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  deadly       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  deadly       the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from -- the ladder is not in the output, so the only place it can be shown to be dead, AND shown to run under SA_NODEFER, is the input"

# tools/phaserun.sh sweeps next, then runs pipes/zero17-check.sh.
