#!/bin/sh
# Zero phase 23, the check -- `nullptr` and `usize`.
# See pipes/zero23-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero23-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero23-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# THIS PHASE CHANGES NO STATEMENT, so there is no behavioural probe to offer and none is
# offered.  What it has instead is stronger than any recording: THE BINARY IS THE SAME
# BYTES.  That is tier 1 of CLAUDE.md's verification table, and it subsumes every screen
# case, every Ex-command row, every command line and every pty scenario at once, because
# the program that would be run is literally the same program.  tools/zerodelta.sh
# --phase 23 still runs, from tools/phaserun.sh after this check, and corroborates; it
# is not the evidence.  It is phase 16's shape exactly, on three thousand edits instead
# of seven.
#
# WHAT IS CLAIMED, in five parts:
#
#   ARITHMETIC  the counts are computed FROM THE INPUT and not written here: every
#               `NULL` outside a literal became a `nullptr`, every `size_t` became a
#               `usize`, the three literals are UNCHANGED, and `usize` gained exactly
#               one for its own typedef.  So the check is about this phase and not about
#               whatever it was handed.
#   LANGUAGE    the typedef is taken OUT OF THE OUTPUT and compiled four ways: gcc's
#               default and `-std=c23` must ACCEPT it, `-std=c11` and `-std=c99` must
#               REFUSE it.  C23 is a real dependency of this file and is stated rather
#               than assumed.  In the same translation unit, with the REAL <stddef.h>
#               arriving after it, `_Generic((usize)0, size_t: 1, default: 0)` proves
#               `usize` IS `size_t` -- the same type, not merely the same width -- and
#               `sizeof(nullptr) == sizeof(void *)` proves the other half of why the
#               thirty casts could go.
#   SYMBOLS     `nm -u` is THE SAME SET, as a `comm` empty in BOTH directions, and `main`
#               is still the only external symbol.  A rename inside one translation unit
#               cannot move either, and a symbol ARRIVING must fail as loudly as one
#               leaving.
#   THE BINARY  `cmp` of the input's binary and the output's, both built with
#               SOURCE_DATE_EPOCH=0 and the boundary's own flags.  This is the whole
#               evidence.
#   THE CONTROL and it is the point.  The same output with the literal exclusion
#               REMOVED -- a plain `\bNULL\b` -> `nullptr` over the whole text, which
#               rewrites the three strings -- MUST give a different binary.  Measured:
#               1,598 bytes differ, 1,354 of them in `.rodata`, and `strings` reports
#               `[nullptr]`, `nullptr` and an E1507 message that names a C keyword at
#               the user.  Without that control the `cmp` above is a pair of numbers
#               agreeing, and CLAUDE.md is explicit that a test that cannot fail is not
#               evidence.
#
# AND ONE CONTROL THAT MOVES NOTHING, REPORTED RATHER THAN DROPPED.  Reverting one
# `usize` to `size_t` compiles cleanly and gives a byte-identical binary, because the
# `#include`s are still at the TOP of the file and `size_t` is therefore still declared
# above every line of it.  That is the honest statement of what this phase's evidence
# cannot reach: the rename is not yet load-bearing, and it becomes so at phase 26, where
# the same control is three hard errors.  It is phase 22's b3/b4 in this phase's shape.

# THE BODY IS GO: tools/go/internal/check/zero23.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zerodelta.sh
set -eu

work=${1:?usage: zero23-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero23-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero23 "$work" "$state"
