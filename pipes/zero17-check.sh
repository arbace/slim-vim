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

# THE BODY IS GO: tools/go/internal/check/zero17.go and tools/go/internal/check/zero17evidence.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/phasecheck.sh
#   tools/st.sh
set -eu

work=${1:?usage: zero17-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero17-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero17 "$work" "$state"
