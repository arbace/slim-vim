#!/bin/sh
# Zero phase 37, the check -- the degenerate unions go.
# See pipes/zero37-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero37-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero37-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# THIS PHASE CHANGES NO STATEMENT AND NO LAYOUT, so there is no behavioural probe to
# offer and none is offered.  What it has instead is stronger than any recording: THE
# BINARY IS THE SAME BYTES.  That is tier 1 of CLAUDE.md's verification table, and it
# subsumes every screen case, every Ex-command row, every command line and every pty
# scenario at once, because the program that would be run is literally the same program.
# It is phase 16's and phase 23's kind of empty declaration -- THE STRONGEST OF THE FIVE
# and not the weakest -- and this check says which kind it is rather than leaving a
# reader to guess.
#
# WHAT IS CLAIMED, in eight parts:
#
#   ARITHMETIC  the whole of it is RECOMPUTED FROM THE INPUT by the edit's own scanner,
#               run again here: the input's thirteen unions are classified by member
#               count, the six with fewer than two members must be gone and the seven
#               with two or more must survive BYTE FOR BYTE, each degenerate name must
#               keep its declaration and every `.member` access on it must be a plain
#               field reference.  Not one of those numbers is written in this file, which
#               is the lesson phase 35 was taught when phase 34 moved its counted
#               anchors.
#   THE DIALECT the empty union's own argument, MEASURED.  `union { } es_info;` is a GNU
#               C extension: gcc reports `union has no members [-Wpedantic]` on the input
#               exactly once and on the output not at all, with the rest of the pedantic
#               diagnostic set unmoved, and a minimal probe shows the same construct is a
#               hard ERROR under `-pedantic-errors` while its non-empty twin is silent.
#   SYMBOLS     `nm -u` is THE SAME SET, as a `comm` empty in BOTH directions, and `main`
#               is still the only external symbol.  Deleting a wrapper type inside one
#               translation unit cannot move either, and a symbol ARRIVING must fail as
#               loudly as one leaving.
#   THE CUT     `awk '/^ *# *include / { exit }'`, zero.mk's own rule, on the INPUT and on
#               the OUTPUT: 0 directives and 0 errors under `-fsyntax-only` either side,
#               and the warning set -- which IS the core -> host interface -- IDENTICAL,
#               computed at run time from the input and never written down.
#   THE BINARY  `cmp` of the input's binary and the output's, both built with
#               SOURCE_DATE_EPOCH=0 and the boundary's own flags.  This is the whole
#               evidence.
#   THE CONTROL and it is the point.  c1 is this phase's own output with the two fields it
#               PROMOTED -- `uh_next` and `uh_prev` -- exchanged: a pure layout
#               permutation of the very struct this phase rewrites, which compiles and
#               must give a DIFFERENT binary.  Measured: 31,038 bytes differ.  Without it
#               the `cmp` above is a pair of numbers agreeing, and CLAUDE.md is explicit
#               that a test that cannot fail is not evidence.
#   TWO THAT MOVE NOTHING, REPORTED RATHER THAN DROPPED.  c2 puts the EMPTY union back
#               and c3 puts one SINGLE-MEMBER union back with its `.member` accesses --
#               this phase run backwards on one field each.  Both must be byte-identical,
#               which is the phase's own claim stated in the other direction: a union of
#               one member and a plain field are the same program, and an empty union is
#               no program at all.  If either ever moves, this phase's account of itself
#               has to be rewritten rather than the number quietly updated.
#   STRUCTURE   tools/canon.sh is a no-op on the output, and `zhostonly` -- phase
#               20's structural check -- still passes.
#
# AND TWO FULL RECORDINGS, WHICH ARE A CHECK ON THE HARNESS AND NOT ON THE PHASE.  With a
# byte-identical binary a `tools/zrecord.sh` of each side compares a program with itself,
# so an empty `diff -r` says the instrument is deterministic and says nothing about the
# edit.  They are run because it is cheaper to measure that than to assert it, and this
# comment is what keeps them from being read as the evidence.  The evidence is the `cmp`.

# THE BODY IS GO: tools/go/internal/check/zero37.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/canon.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero37-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero37-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero37 "$work" "$state"
