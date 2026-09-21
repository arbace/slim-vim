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

# THE BODY IS GO: tools/go/internal/check/zero30.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/canon.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zpty.py
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero30-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero30-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero30 "$work" "$state"
