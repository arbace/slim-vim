#!/bin/sh
# Zero phase 16, the check -- the includes nothing names.
# See pipes/zero16-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero16-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero16-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# and `old`, that source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# THIS PHASE CHANGES NO CODE, so there is no behavioural probe to offer and none is
# offered.  What it has instead is stronger than any recording: THE BINARY IS THE SAME
# BYTES.  That is tier 1 of CLAUDE.md's verification table -- "pure formatting: the
# binary is byte-identical (cmp)" -- and a byte-identical binary subsumes every screen
# case, every Ex-command row, every command line and every pty scenario at once, because
# the program that would be run is literally the same program.  tools/zerodelta.sh
# --phase 16 still runs, from tools/phaserun.sh after this check, and it corroborates;
# it is not the evidence.
#
# THE ARGUMENT IS A COMPUTATION AND NOT A LIST, and section 3 is the whole phase.  A
# phase that deleted six named headers proves only that six named headers were
# deletable.  What this proves is EVERY INCLUDE THAT SURVIVES IS NEEDED and EVERY
# INCLUDE THAT WENT WAS NOT, by removing each one in turn and asking the compiler:
#
#   on the output    12 compiles, and EVERY ONE MUST FAIL.  A dead include that
#                    survived this phase would be a compile that succeeded.
#   on the input     18 compiles, and EXACTLY SIX MUST SUCCEED -- the six this phase
#                    removed -- while the other twelve fail.  That is the same loop
#                    proving it can fail, in the same run, on the same code path: it
#                    is phase 13's ui_write() control in this phase's shape.
#
# Measured: the two loops together are 30 compiles and about 5 seconds, run at once.
# gcc 15 defaults to C23, where an implicit function declaration is a HARD ERROR, so a
# header that still supplies a function, a type, a macro constant or an enum constant
# cannot be dropped quietly -- there is no -Wimplicit-* to look for because there is
# nothing left to warn about.
#
# THE ONE SILENT DROP IN THIS FILE, and section 2 is where it is caught.  Removing
# <sys/stat.h> while keeping `typedef struct stat stat_T;` COMPILES CLEANLY: the typedef
# declares a new, incomplete `struct stat` at file scope.  Only `sizeof(stat_T)` would
# ever have exposed it.  So the typedef is required at zero mentions and `struct stat`
# with it, and section 3's loop would NOT have caught this one on its own.
#
# WHAT MUST NOT MOVE, and each is asserted rather than assumed:
#
#   * the libc surface, as a `cmp` OF THE WHOLE SET.  This phase frees nothing and
#     nothing arrives -- it is phase 5's, 11's and 12's equality, and a symbol
#     ARRIVING must fail as loudly as one leaving.
#   * `main` the only external symbol (tools/phasecheck.sh).  Phases 14 and 15 added
#     twenty-eight `static` definitions of what were libc functions, and that check is
#     what says the keyword was not forgotten; this phase re-asserts it for free.
#   * `FILE` at zero mentions, and nothing that could open or name a file called --
#     ZERO-PLAN.md 4b's invariant, which <fcntl.h> and <sys/stat.h> leaving makes
#     visible in the directive list for the first time.
#   * `cmdnames[]`, `nv_cmds[]` and `options[]`, none of which this phase touches.
#   * the blank-line paragraphing, which no verification tier can see: CLAUDE.md says
#     this tree has no run of two blank lines, and deleting the typedef between its two
#     blanks would have made one.
#
# WHY THE cmp IS AS SENSITIVE AS IT IS.  gcc writes a GNU build-id note near the front
# of the image, and it is a hash of the whole output -- so ANY difference anywhere moves
# it and the FIRST difference cmp reports is always that note, at char 633 of this
# binary.  Measured three ways on the stand-in: two ordinary builds of the same bytes
# differ there (which is why SOURCE_DATE_EPOCH=0 is set on both sides), a one-character
# change to one string literal differs there, and the phase's own output does not differ
# at all.

# THE BODY IS GO: tools/go/internal/check/zero16.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zerodelta.sh
set -eu

work=${1:?usage: zero16-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero16-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero16 "$work" "$state"
