#!/bin/sh
# Zero phase 18, the check -- main() is demoted to vim_main().
# See pipes/zero18-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero18-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero18-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# and `old`, that source built with the boundary's own flags.
#
# WHAT IS CLAIMED is that the editor now runs one call frame deeper and nothing else
# is different.  There are three things that could make that false and each has its
# own assertion:
#
#   * the LINKAGE.  `vim_main` must be static, so `nm --extern-only --defined-only`
#     still prints exactly `main` -- which tools/phasecheck.sh asserts for every zero
#     phase and which section 3 re-states here in the phase's own words.
#   * the LIBC SURFACE.  A phase that frees nothing says so as an EQUALITY, the way
#     phases 7, 8, 11, 12 and 16 do: the undefined set before and after is compared
#     with `cmp` and must be the same 33 names in the same order, not the same COUNT.
#   * the EXIT STATUS.  `return vim_main(argc, argv);` is a value this phase put in
#     the program's path that was not there before, so every way the editor can end
#     is probed on BOTH binaries and required to agree: `:q!` 0, `:cq 3` 3, EOF 1, a
#     bad option 1, SIGTERM 1, SIGHUP 1.
#
# AND THE PROBE IS PROVEN ABLE TO FAIL.  A table of six statuses that agree proves
# nothing unless a wrong status would have been caught, so the output is built a
# SECOND time with `mch_exit`'s `exit(r)` changed to `exit(r + 1)` -- one character --
# and every one of the six is required to MOVE.  That is phase 17's `SA_NODEFER`
# control in this phase's shape: the same source with the reason removed.
#
# THE BINARY IS NOT BYTE-IDENTICAL AND IS NOT ASSERTED TO BE.  At -O0 a call frame is
# real code: `main` now pushes a frame and calls `vim_main`, where it used to be
# `vim_main`'s body outright.  Measured, both built SOURCE_DATE_EPOCH=0 with the
# boundary's flags: 805,544 bytes either side -- the same SIZE, absorbed by alignment
# padding, and different bytes.  So the size is reported and the identity is not
# claimed; what is compared is the symbol set, the exit statuses and the recording.

# THE BODY IS GO: tools/go/internal/check/zero18.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/phasecheck.sh
#   tools/st.sh
set -eu

work=${1:?usage: zero18-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero18-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero18 "$work" "$state"
