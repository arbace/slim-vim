#!/bin/sh
# Zero phase 31, the check -- abs and labs, the two the core took on trust.
# See pipes/zero31-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero31-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero31-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# `nm -u` CANNOT MOVE HERE, AND THAT IS THE PHASE.  A vendoring phase that leaves the
# symbol count alone reads like a failure, so this check states it as an equality and
# says why: `abs` and `labs` were called by the core at three sites and were in `nm -u`
# ZERO times, because gcc lowers both to inline arithmetic.  Section 5 measures that
# rather than asserting it -- `gcc -S` of the INPUT contains not one mention of either
# name -- and that is exactly the problem.  Nothing in the language promises it.  A
# compiler that emitted the calls the source asks for would have added two libc symbols
# to a file whose whole claim is the shortness of that list, and no check in this
# pipeline would have said so until it happened.  ZERO-PLAN.md 4c: the core is
# optimised for transpilation, not for performance, and may not depend on latent
# compiler behaviour.
#
# WHAT IS CLAIMED, in seven parts:
#
#   ARITHMETIC  computed FROM THE INPUT: `abs` and `labs` are 0 in the output where the
#               input had 2 and 3, `musl_abs` is 2 and `musl_labs` 3, the core's libc
#               declaration block loses exactly those two entries, both definitions
#               begin at column 0 ABOVE the boundary, and the file is ten lines longer.
#   THE SAME FUNCTION
#               musl writes `a>0 ? a : -a` and this copies it rather than turning it
#               round, and the check proves the choice is free TWICE: the two spellings,
#               taken OUT OF THE OUTPUT, compile to BYTE-IDENTICAL machine code at -O0
#               and at -O2, and they agree at all 4,294,967,296 `int` values and at
#               20,000,006 `long` ones including LONG_MIN and LONG_MAX.
#   THE UB      `-a` overflows at INT_MIN and LONG_MIN, so both vendored functions are
#               undefined there -- and so are libc's, by the same expression, which is
#               why the pair is FAITHFUL RATHER THAN SAFER.  What is measured is whether
#               the three call sites can reach the value, and section 7 answers it: the
#               largest magnitude any of them is ever handed, across 106 records and 51
#               probe calls, is 22.  The static reason is in the file -- window heights
#               are clamped by `limit_screen_size()` at 1,000 rows, and the two `labs`
#               arguments are differences of line numbers, which are >= 1.
#   CANON       tools/canon.sh is a NO-OP: the two definitions are written the way this
#               file writes every other function, name at column 0 and all.
#   THE BOUNDARY
#               `make editor.c`'s cut, computed here by the same awk clause: 0
#               directives, `-fsyntax-only` with no error and no warning that is not a
#               boundary name, and THE SET OF NAMES TAKEN FROM THE INPUT'S OWN CUT and
#               required back -- never written out, because phase 28 renamed one of them
#               and a check that quotes a list is a check that goes stale in silence.
#   THE BINARY  IT MOVES, and no `cmp` is attempted: at -O0 a call to a static function
#               is a call and inline arithmetic is not.  What is asserted instead is
#               that the difference is ACCOUNTED FOR INSTRUCTION BY INSTRUCTION --
#               `musl_abs` + `musl_labs` + the three callers' size changes = the
#               object's whole `.text` delta -- and that every section of the linked
#               image keeps its size and its address.
#   BEHAVIOUR   two full recordings byte-identical; AND THE CORPUS CANNOT SEE THIS PHASE
#               AT ALL, measured -- an instrumented build enters none of the three call
#               sites in 106 records.  So the phase owes probes, and it runs three, one
#               per site, on the binary it was handed and on its own.
#
# THE PROBES, and each is a way of reaching a site nothing else here reaches:
#
#   rnu   `+set rnu`, sixty lines, `gg`     46 calls at the number column's labs,
#                                          arguments from -21 to 22
#   sms   sixty long wrapped lines, then    3 calls at scroll_with_sms's labs,
#         CTRL-F CTRL-F CTRL-B CTRL-B       arguments -6 and 5
#   stl   `:set laststatus=2` then `=0`     2 calls at last_status_rec's abs, -1 and 1
#
# AND TWO OF THE THREE ARE PROVEN ABLE TO FAIL, by a control whose `musl_abs` and
# `musl_labs` return their argument unchanged: `rnu` moves by 15 bytes and `sms` moves.
# `stl` DOES NOT MOVE AND THAT IS REPORTED RATHER THAN HIDDEN -- the site is reached
# twice and its answer guards only `w_prev_height = w_height`, an assignment
# `win_new_height()` already makes on every path that changes a height, so no session
# tried here draws anything different.  The site is proven REACHED and not proven
# OBSERVABLE, and the phase's real evidence for it is section 2: it is the same
# function.

# THE BODY IS GO: tools/go/internal/check/zero31.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/canon.sh
#   tools/funcreach.py
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/symbols.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero31-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero31-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero31 "$work" "$state"
