#!/bin/sh
# Zero phase 31 -- abs and labs, the two the core took on trust.
# See ZERO-PLAN.md 4c, and ZERO-GOAL.md.
#
# Usage: pipes/zero31-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# THE CORE IS OPTIMISED FOR TRANSPILATION, NOT FOR PERFORMANCE, AND SO IT MAY NOT
# DEPEND ON LATENT COMPILER BEHAVIOUR (ZERO-PLAN.md 4c, the user's rule of
# 2026-09-19).  This phase is the first application of it, and it is the reason the
# phase exists at all -- because by every number this pipeline usually reports, it
# does nothing.
#
# `abs` and `labs` are CALLED by the core, at three sites, and appear in `nm -u`
# ZERO times.  gcc lowers both to inline arithmetic -- measured on the input, `gcc
# -S` of the whole file contains not one mention of either name -- and NOTHING IN
# THE LANGUAGE PROMISES THAT.  A compiler that emitted the calls the source
# literally asks for would silently have added two libc symbols to a file whose
# whole claim is the shortness of that list.  So this phase FREES NO SYMBOL and must
# say so as an equality rather than let a reader expect a vendoring phase to move
# the count: what it removes is a dependence on behaviour nothing states.
#
# WHAT IT DOES, in three parts:
#
#   the two prototypes    `long labs(long n);` and `int abs(int n);`, which zero
#                         phase 26 wrote into the core's block of libc declarations
#                         when the headers were still above it.  The block loses two
#                         of its entries and nothing else changes in it.
#   the three call sites  8152 `musl_labs((long)get_cursor_rel_lnum(...))` in the
#                         number column, 41824 `musl_labs(curwin->w_topline -
#                         prev_topline)` in scroll_with_sms, and 77379
#                         `musl_abs(wp->w_height - wp->w_prev_height)` in
#                         last_status_rec.  The line numbers are where they were
#                         when this was written and nothing below depends on them.
#   the two definitions   `static musl_abs` and `static musl_labs`, in the `musl_`
#                         block phases 14 and 15 built, immediately above
#                         `musl_bsearch` so that the four `<stdlib.h>` scalar
#                         functions the core owns -- musl_atoi, musl_atol, musl_abs,
#                         musl_labs -- sit together and above every use.
#
# MUSL'S SPELLING IS COPIED AND NOT IMPROVED, which is phase 14's rule applied to
# two more functions.  /root/musl/src/stdlib/abs.c and labs.c are one line each:
#
#     int abs(int a) { return a>0 ? a : -a; }
#     long labs(long a) { return a>0 ? a : -a; }
#
# `a > 0 ? a : -a` and `a < 0 ? -a : a` ARE THE SAME FUNCTION, and the check proves
# it twice rather than arguing it: the two spellings compile to BYTE-IDENTICAL
# machine code at -O0 and at -O2, and they agree at every one of the 4,294,967,296
# `int` values.  Having established that, the rule is to write what musl writes.
#
# AND THE UNDEFINED BEHAVIOUR IS COPIED WITH IT.  `-a` overflows at `INT_MIN` and at
# `LONG_MIN`, so `musl_abs(INT_MIN)` is undefined -- and so is `abs(INT_MIN)`, and so
# is musl's own `abs`, by exactly the same expression.  THE VENDORED PAIR IS
# FAITHFUL RATHER THAN SAFER, deliberately: a phase that quietly made the core's
# arithmetic differ from the libc it is replacing would be a behaviour change
# wearing a vendoring phase's clothes.  What the check does instead is measure
# whether the three call sites can reach the value, and the answer is no in one case
# by a clamp in this file and in the other two by the arithmetic of line numbers.
#
# THE INPUT BINARY IS BUILT HERE with SOURCE_DATE_EPOCH=0, and the check needs it for
# more than a comparison: the corpus CANNOT SEE any of the three call sites (measured
# -- an instrumented build enters none of them in 106 records), so this phase owes
# probes of its own, and those probes are run on the binary this phase was handed and
# on its own and required to draw the same screen.
set -eu

work=${1:?usage: zero31-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero31-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero31 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  arith        the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  arith        the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from.  THE BINARY WILL MOVE and no cmp is attempted: at -O0 a call to a static function is a call and inline arithmetic is not, so the check accounts for the difference instruction by instruction and takes its behavioural evidence from recordings and from probes"

# tools/phaserun.sh sweeps next, then runs pipes/zero31-check.sh.
