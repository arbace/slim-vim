#!/bin/sh
# Zero phase 35, the check -- the core calls nothing but the host.
# See pipes/zero35-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero35-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero35-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# WHAT IS CLAIMED, in nine parts:
#
#   ARITHMETIC  computed FROM THE INPUT and not written here: above the boundary
#               every mention of the three is the declaration or a call, the declaration
#               goes and EVERY call becomes the host name, so each ends at 0 above the
#               boundary and each host name at its prototype plus those calls plus its
#               definition.  Below it 0 -> 1, 1 -> 2 and 1 -> 2: the phase MOVES three
#               libc calls and frees none.  HOW MANY calls is read off the input.  The
#               core's block of ordinary declarations loses exactly those three lines
#               and keeps every other, and what remains is PRINTED, because an empty
#               block is this phase's whole point and a check that asserted emptiness
#               against a file that still had other libc in it would be asserting
#               somebody else's phase.
#   THE ORDER   each prototype is above every call of its name and each definition below
#               every one of them AND below the boundary, by line number.  The control
#               is the output with the three prototype lines DELETED, which must not
#               compile and must name all three.
#   LINKAGE     `nm --extern-only --defined-only` is still exactly `main`, with both
#               halves of the `static` trap built: with the keyword off the three
#               PROTOTYPES gcc refuses, and with it off the prototypes AND the
#               definitions the build is silent and three symbols become external.
#   SYMBOLS     `nm -u` is THE SAME SET, as a `comm` empty in BOTH directions.  A phase
#               that takes every `malloc`, `free` and `write` out of the core frees
#               NOTHING, and that is not a disappointment: the host calls all three, and
#               an undefined symbol leaves when its last caller leaves the FILE.  Phase
#               28 is the contrast -- it freed `gettimeofday` because the last caller
#               went -- and a reader who expects this phase to move the count is owed
#               the equality with its reason.
#   THE CUT     `awk '/^ *# *include / { exit }'`, zero.mk's own rule, on the INPUT and
#               on the OUTPUT: 0 errors under -fsyntax-only either side, and the warning
#               set -- which IS the core -> host interface, every name `used but never
#               defined` -- grows by EXACTLY `host_alloc host_free host_write`.  The
#               input's set is computed here and never written down: it has gone stale
#               twice for other phases.
#   THE BINARY  the same SIZE and NOT the same bytes, both stated as measurements.
#   THE RECORD  two full tools/zrecord.sh recordings, `diff -r` empty over 106 records,
#               with a control that moves all 106.
#   THE PROBES  ONE PER FUNCTION, on an instrumented build of this phase's own output,
#               because a byte-identical recording says the editor did the same thing
#               and not that these three carried it.  Over the 102 screen cases the
#               instrument counts every call, the largest allocation, the largest write
#               and every short write; and three sessions drive the paths by hand -- a
#               200,000-character insert, a free of a null pointer, and the largest
#               write the corpus can produce.
#   STRUCTURE   `zhostonly`, phase 20's structural check, still passes.

# THE BODY IS GO: tools/go/internal/check/zero35.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/canon.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero35-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero35-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero35 "$work" "$state"
