#!/bin/sh
# Zero phase 32 -- the clock crosses the boundary.
# See ZERO-PLAN.md 4c, ZERO-GOAL.md, pipes/zero26-edit.sh (which wrote the core's libc
# prototypes) and pipes/zero28-edit.sh (the scalar clock, whose musl_now_ms is this
# phase's sibling).
#
# Usage: pipes/zero32-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# THE CORE READS TWO CLOCKS AND ONLY ONE OF THEM HAS CROSSED.  Phase 28 gave the
# elapsed-milliseconds clock to the host as `long musl_now_ms(void)`.  The other one --
# the wall clock, `time(2)`, which the editor stamps a history entry and an undo header
# with -- is still the core's: `time_T vim_time(void) { return time(nullptr); }` at
# five call sites, `long time(long *tp);` in the core's own libc prototype block, and
# TWO MORE CALLS THAT BYPASS THE WRAPPER ALTOGETHER, inside `ui_focus_change()`.  This
# phase is the user's two steps, in order.
#
#   STEP ONE   the two standalone `time(nullptr)` in ui_focus_change become `vim_time()`.
#              After it, `time(` has exactly ONE call site above the boundary: the one
#              inside the wrapper.
#   STEP TWO   the wrapper moves below the boundary as `host_time()`, declared in the
#              core's host block beside host_exit, host_message and the musl_ set, and
#              `long time(long *tp);` leaves the core -- the host takes `time` from
#              <time.h>, which is one of the eleven includes.
#
# THE PROTOTYPE IS LOAD-BEARING AND REMOVING IT WOULD SILENTLY REGRESS.  `typedef long
# time_T;` is phase 26's, and it is correct ONLY because `long time(long *tp);` sits
# above <time.h>'s own declaration of the same function: gcc compares the two and says
# `conflicting types for 'time'` if they disagree -- MEASURED by phase 26's `m1`
# control, and measured again here.  Phase 26's sixteen static_asserts were a control in
# ITS check and are NOT in the product (the twelve that survive below the includes are
# phase 27's constants), so once the prototype goes there is nothing left comparing the
# core's width to the host's, and `host_time()` returning a narrower type than `time_t`
# would truncate in silence on a target where the two differ.  So the prototype is
# REPLACED, not merely deleted:
#
#     static_assert(_Generic((time_T)0, time_t: 1, default: 0), "time_T is time_t");
#
# below the includes, beside the twelve.  pipes/zero32-check.sh measures that it holds
# AND that it fails when `time_T` is perturbed to `int` -- a guarantee you cannot break
# is not one.
#
# `host_time()` RETURNS `long`, NOT `time_T`, AND THAT IS A DECISION.  Its DEFINITION is
# below the boundary, and `time_T` is a core typedef declared above it: when the file is
# finally cut at the first `#include` the host half cannot name it.  `musl_now_ms()`
# returns `long` for exactly that reason and this is its sibling, so the two halves of
# the clock cross in the same shape -- and the boundary's stated property, that every
# core -> host signature takes scalars and byte buffers only (pipes/zero28-check.sh),
# survives a fourteenth name.  Nothing is converted at any call site: `time_T` IS `long`
# in this file, the check asserts the typedef line itself, and the static_assert above
# pins that `long` to `time_t`.
#
# WHAT DOES NOT CHANGE, AND THE CHECK MEASURES IT RATHER THAN ARGUING IT.
# `ui_focus_change()` reads the clock TWICE, in two separate statements --
# `if (in_focus && last_time + 2 < ...)` and then `last_time = ...` -- and it still
# does: two reads, the same two statements, the same order.  The pair could always
# straddle a second boundary between the test and the store, and it can still, neither
# more nor less often: what changes is the spelling of the read, not how many there are
# or when.  pipes/zero32-check.sh instruments every clock read on BOTH binaries and
# requires the same count in the same records, with a control that collapses the two
# reads into one and moves it.
#
# THE ENGLISH WORD `time` IS NOT A CALL.  `op_shift()`'s NGETTEXT strings say "%ld line
# %sed %d time" / "times", and ``zhostonly`` learned the same lesson about
# `"close buffer"`: every count here is taken with string and character literals blanked
# out, and the substitutions are exact multi-line blocks, never a bare `time` -> anything.
set -eu

work=${1:?usage: zero32-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero32-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero32 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  wallclock    the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  wallclock    the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- a call replaces an inlined one and 5 lines of definition move past 2,000, so the binary WILL move and no tier 1 equality is available: the recording answers, and the instrumented pair answers for the two reads"

# tools/phaserun.sh sweeps next, then runs pipes/zero32-check.sh.
