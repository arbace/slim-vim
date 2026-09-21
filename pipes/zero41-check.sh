#!/bin/sh
# Zero phase 41, the check -- freeing is free.  See pipes/zero41-edit.sh, and
# ZERO-GOAL.md's charter bullet "A GARBAGE COLLECTOR IS ASSUMED FROM HERE ON".
#
# Usage: pipes/zero41-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero41-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags, and `arena-bytes`.
#
# WHAT IS CLAIMED, in eleven parts:
#
#   ARITHMETIC  `malloc`, `free` and `realloc` are 0 mentions in the whole file, stated
#               as a PARTITION of the input's mentions rather than as counts, and every
#               name the phase writes is defined exactly once.
#   THE CUT     `make editor.c`'s own rule on the input and on the output, and they are
#               BYTE-IDENTICAL.  That is the whole of "this phase touches no core line",
#               and it is the cleanest thing this phase can say: the program the project
#               is FOR is literally the same program.  Its warning set -- the core -> host
#               interface -- is the same names either side, which follows.
#   SYMBOLS     `nm -u` loses EXACTLY `free malloc realloc` and nothing else moves, as a
#               `comm` in both directions against the stage's snapshot.  17 -> 14.  Two
#               of the three are the allocator; the third is the one phase 34 left below
#               the boundary and phase 35 left with it.
#   THE IMAGE   EXEC, no INTERP, no dynamic section, no relocation -- phases 0 and 1's
#               four facts, which a gigabyte object could have disturbed and does not.
#               `.bss` grows by the arena and THE FILE SHRINKS, both as measurements:
#               `.bss` is NOBITS and musl's allocator is no longer linked in.
#   THE RECORD  two full tools/zrecord.sh recordings, `diff -r` empty over 106 records,
#               with a control that moves all 106.
#   THE ARENA   the high-water the corpus really asks for, measured by an instrument on
#               THIS PHASE'S OWN OUTPUT over all 102 screen cases, and required to sit
#               well inside the arena.  The size is a checked property here and not a
#               number remembered from the edit's header.
#   THE GUARD   an arena deliberately too small must ABORT, with a message naming the
#               arena, what is used and the request that did not fit, and a non-zero
#               status -- and the same session on the real output must be silent and
#               exit 0.  Without this the abort is a branch nobody has ever taken.
#   THE BUMP    the offset never advancing must move every screen case.  A bump allocator
#               whose bookkeeping did nothing would hand the same block out twice and
#               still pass every test above, and this is what says it does not.
#   host_free   PHASE 35'S OWN CONTROL, RE-RUN ON THIS PHASE'S INPUT AND NOT REINVENTED:
#               `cf`, host_free doing nothing, which phase 35 measured at 0 of 102.  It
#               is the same 0 here, and it is REPORTED rather than hidden -- a leak is
#               invisible to this corpus, so the recording above is NOT what says the
#               freeing changed, and nothing in this check pretends it is.
#   THE PROBE   the two rewrites below the boundary that no recording can reach.  A
#               driver built into the input AND the output drives six positional formats
#               through adjust_types(), entering the grow arm this phase rewrote, and the
#               two binaries must print the same bytes.
#   <stdlib.h>  MEASURED AND DECLINED.  With malloc, free and realloc gone the directive
#               is dead, and the output built without it is BYTE-IDENTICAL.  It stays:
#               phase 13's precedent, and this phase's subject is the allocator.

# THE BODY IS GO: tools/go/internal/check/zero41.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/canon.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero41-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero41-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero41 "$work" "$state"
