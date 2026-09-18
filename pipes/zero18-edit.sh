#!/bin/sh
# Zero phase 18 -- main() is demoted to vim_main().  See ZERO-GOAL.md.
#
# Usage: pipes/zero18-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# The editor's entry point stops being the program's entry point.  What was
#
#         int
#     main
#     (int argc, char **argv)
#     {
#         ...
#         return vim_main2();
#     }
#
# becomes `static int vim_main(int argc, char **argv)` with the SAME BODY, and a new
# five-line `main()` at the bottom of the file whose whole content is
# `return vim_main(argc, argv);`.  Nothing else moves.  This is ZERO-PLAN.md 4c's
# first step, and it is deliberately the ONLY thing this phase does: the host
# boundary is a sequence of small demotions and this is the one that names them.
#
# BOTH STAY IN zero-vim.c, AND THAT IS THE POINT RATHER THAN A COMPROMISE.  Two
# tools hard-code today's invariant -- tools/phasecheck.sh's `grep -v '^main$'` and
# tools/funcreach.py's `{'main'}` root -- and splitting the launcher into a second
# translation unit is what breaks both.  Measured while `exit` was being reviewed:
# ONE APPENDED LINE to tools/phasecheck.sh moves 118 implementation keys (12 whim
# stages, 82 whim edits, 12 zero units, 12 zero edits, and no slim key).  So every
# demotion that CAN be done inside one file is done inside one file, and the split
# happens once, late, when there is nothing left to do before it.
#
# `vim_main` IS static, and that is what keeps the invariant exact.  The check asserts
# `nm --extern-only --defined-only` prints `main` and nothing else, which it has for
# every zero phase; a non-static `vim_main` would be the first zero phase ever to add
# an external symbol, and it would do it for no reason -- nothing outside this file
# calls it yet.
#
# THE NAME WAS CHECKED FOR A COLLISION BEFORE IT WAS CHOSEN.  `vim_main2()` already
# exists in this file -- it is upstream's, the second half of the old main() split at
# the point where the screen is up -- and `vim_main` is a DIFFERENT identifier, not a
# prefix collision: C has no such thing.  The assertions below pin `vim_main2` at its
# two mentions and require `vim_main` to have had NONE before this phase, both as
# whole words, so the two cannot be confused by a substring grep either.
#
# THE HEAD IS A FOSSIL AND THIS PHASE RETIRES IT.  main()'s head is spelled over THREE
# lines here --
#
#         int
#     main
#     (int argc, char **argv)
#
# -- which is upstream's, where the name and the argument list were separated by an
# `#ifdef` that gave MS-Windows a different signature.  The conditional went with the
# preprocessor in slim's phase 5 and the line break stayed.  Every other function in
# this file spells its head over two lines, so `vim_main` gets the ordinary shape and
# the new `main` gets it too.  That is a real consequence, measured and not cosmetic:
# tools/funcreach.py's definition finder never matched the three-line head, so `main`
# has never been one of the definitions it counts -- its `{'main'}` root was a name
# added by hand to a set that did not contain it.  1,755 definitions become 1,757 for
# ONE new function, and the second is `main` itself, seen for the first time.
set -eu

work=${1:?usage: zero18-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero18-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).  The
# input binary is kept because the check probes the exit statuses of BOTH.
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

python3 - "$f" <<'PY'
TAG = 'demote'
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


lines_before = len(t.split('\n'))
runs_before = blank_runs(t)

# ---- 1. the name is free, and `vim_main2` is not it ---------------------------------
# C has no prefix collisions, but a reader greps, and so does this file's own
# machinery.  `vim_main` must not exist and `vim_main2` must be exactly what it is.
if mentions(t, 'vim_main'):
    die('`vim_main` already has %d mentions as a whole word -- the name this phase '
        'gives the editor is taken' % mentions(t, 'vim_main'))
if mentions(t, 'vim_main2') != 2:
    die('`vim_main2` has %d mentions, expected 2 -- its definition and the one call at '
        "the bottom of main().  It is upstream's second half of main(), it is NOT the "
        'name this phase introduces, and pinning it is what keeps a substring grep '
        'from confusing the two' % mentions(t, 'vim_main2'))
once('    static int\nvim_main2(void)\n{\n', "vim_main2()'s definition",
     'it is the function the new vim_main() ends by calling, and it does not move')
say('`vim_main` is free -- ZERO mentions as a whole word -- and `vim_main2` is the two '
    'it has always had: upstream\'s second half of main(), which this phase does not '
    'touch.  They are different identifiers and C has no prefix collision')

# ---- 2. main() is where and what this phase was written against ----------------------
# The three-line head is upstream's `#ifdef`ed signature with the conditional gone.
HEAD = '\n    int\nmain\n(int argc, char **argv)\n{\n'
once(HEAD, "main()'s three-line head",
     'the name sits on a line of its own because upstream had an #ifdef between it '
     'and the argument list; slim\'s phase 5 took the conditional and left the break')
if mentions(t, 'main') != 1:
    die('`main` as a whole word has %d mentions, expected 1 -- the definition below is '
        'the ONLY place this file writes the bare word.  `main_loop`, `main_errors`, '
        '`vim_main2` and `domain` are different words and \\b does not match inside '
        'them' % mentions(t, 'main'))
if not t.endswith('    return vim_main2();\n}\n'):
    die("zero-vim.c does not end with main()'s `return vim_main2();` and its closing "
        'brace -- CLAUDE.md states that as the shape of this file, and this phase '
        'appends after it')
say('main() is the last function in the file, its head spelled over THREE lines, and '
    '`main` as a whole word occurs ONCE in 80,000 lines -- that one line, the name on '
    'its own.  `main_loop` and `main_errors` are different words')

# ---- 3. the demotion: one head rewritten, one function appended ----------------------
NEWHEAD = '\n    static int\nvim_main(int argc, char **argv)\n{\n'
t = t.replace(HEAD, NEWHEAD, 1)

# The launcher.  Five lines, and every one of them is what ZERO-PLAN.md 4c says the
# host file will hold: it calls the editor and it does nothing else.  No prototype is
# written for vim_main -- it is DEFINED above its only call, so a declaration would be
# one the sweep is entitled to delete.
LAUNCH = ('\n'
          '    int\n'
          'main(int argc, char **argv)\n'
          '{\n'
          '    return vim_main(argc, argv);\n'
          '}\n')
t = t + LAUNCH

# ---- 4. what the file is now ---------------------------------------------------------
once('    static int\nvim_main(int argc, char **argv)\n{\n', "vim_main()'s head",
     'the editor entry point, static, in the two-line shape every other function here '
     'uses')
once(LAUNCH, 'the launcher', 'it is appended once and it is the last thing in the file')
if not t.endswith(LAUNCH):
    die('the launcher is not the last thing in the file')
if mentions(t, 'vim_main') != 2:
    die('`vim_main` has %d mentions, expected 2 -- its definition and the one call from '
        'main().  A third would be a prototype, and a prototype for a function defined '
        'above its only call is redundant' % mentions(t, 'vim_main'))
if mentions(t, 'vim_main2') != 2:
    die('`vim_main2` moved, and this phase does not touch it')
if mentions(t, 'main') != 1:
    die('`main` as a whole word has %d mentions after the demotion, expected 1 -- the '
        "launcher's head and nothing else.  `vim_main` and `vim_main2` are different "
        'words' % mentions(t, 'main'))
if 'main\n(int argc' in t:
    die('the three-line head survives somewhere')
if blank_runs(t) != runs_before:
    die('the demotion left %d runs of two blank lines where there were %d'
        % (blank_runs(t), runs_before))
if len(t.split('\n')) != lines_before + 5:
    die('the file gained %d lines, expected 5 -- the three-line head became two (-1) '
        'and the launcher is six (+6)' % (len(t.split('\n')) - lines_before))
say('main() is now `static int vim_main(int argc, char **argv)` with the same body, and '
    'the last six lines of the file are a launcher whose whole content is `return '
    'vim_main(argc, argv);`.  +5 lines: the fossil head lost one, the launcher added six')

open(path, 'w', errors='surrogateescape').write(t)
PY

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  demote       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  demote       the input is $state/old, $(stat -c%s "$state/old") bytes -- the check probes the exit statuses of BOTH binaries, and a status is only evidence if the binary this phase was handed is required to give the same one"

# tools/phaserun.sh sweeps next, then runs pipes/zero18-check.sh.
