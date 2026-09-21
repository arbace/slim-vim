#!/bin/sh
# Zero phase 36, the check -- the core's libc prototype block empties.
# See pipes/zero36-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero36-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero36-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# WHAT IS CLAIMED, in ten parts:
#
#   ARITHMETIC  computed FROM THE INPUT and not written here.  Above the boundary every
#               mention of `getpid` and `kill` falls in a class this phase rewrites, and
#               both end at 0; `mch_get_pid` and `b0_pid` end at 0, the sweep having
#               taken the prototype and the field the edit orphaned; `host_raise` ends
#               at three, a prototype, a call and a definition.  The core's block of
#               ordinary declarations loses exactly two lines, and what remains is
#               PRINTED, because an empty block is this phase's whole point.
#   THE CLAIM   and it is measured from the CUT, not from the block, because those are
#               two different assertions and only the first is the claim.  A bare
#               `extern` declaration is INVISIBLE to `-fsyntax-only` -- gcc warns `used
#               but never defined` for a `static` function and says nothing about an
#               ordinary one -- so what is measured is `nm -u` of an OBJECT of the cut
#               alone: the set of names the core needs from outside itself.  Every name
#               in it must be DEFINED BELOW THE BOUNDARY in this same file, computed;
#               the identical computation on the INPUT finds exactly two that are not,
#               `getpid` and `kill`, and that is the control.  The cut also defines no
#               external symbol at all.
#   VOCABULARY  `zhostonly`, phase 20's structural check, plus the stronger thing
#               this boundary can say: above the first `#include` the ONLY words of that
#               tool's host vocabulary left are `SIGHUP` and `SIGTERM`, the two the core
#               NAMES because it prints them.
#   THE FOLD    NOT TAKEN, and asserted as a byte comparison rather than left to be
#               believed: `deathtrap()` is identical in and out, and `vim_handle_signal()`
#               differs in exactly one line.  See the edit for the survey.
#   THE ORDER   the prototype is above the call, the definition below it, below the
#               boundary AND inside the host region.  The control is the output with the
#               prototype line deleted, which must not compile and must name it.
#   LINKAGE     `nm --extern-only --defined-only` is still exactly `main`, with both
#               halves of the `static` trap built.
#   SYMBOLS     `nm -u` is THE SAME SET, as a `comm` empty in both directions, and
#               `getpid` and `kill` are both still in it.  A phase that takes the last
#               core mention of two libc names frees NEITHER, because the host calls
#               both and a symbol leaves when its last caller leaves the FILE.
#   THE BINARY  the same SIZE or not, stated as a measurement, and NOT the same bytes.
#   THE RECORD  two full tools/zrecord.sh recordings, `diff -r` empty over 106 records,
#               with one control that MOVES all 106 and one that moves NONE, both on the
#               line this phase deletes.
#   THE PROBES  THE CORPUS CANNOT SEE EITHER HALF OF THIS PHASE, and that is measured
#               rather than assumed: an instrumented input counts the b0_pid write in
#               every one of the 102 screen cases and the re-raise in NONE of them.  So
#               the phase owes probes, and they are a forced deferral driven identically
#               into both binaries, with two controls.

# THE BODY IS GO: tools/go/internal/check/zero36.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/canon.sh
#   tools/deadfields.py
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero36-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero36-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero36 "$work" "$state"
