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

tools/st.sh edit zero17 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  deadly       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  deadly       the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from -- the ladder is not in the output, so the only place it can be shown to be dead, AND shown to run under SA_NODEFER, is the input"

# tools/phaserun.sh sweeps next, then runs pipes/zero17-check.sh.
