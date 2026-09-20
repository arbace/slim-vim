#!/bin/sh
# Zero phase 28 -- the scalar clock.
# See ZERO-PLAN.md 4c, ZERO-GOAL.md, and pipes/zero26-edit.sh, which created the thing
# this phase retires.
#
# Usage: pipes/zero28-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# WHAT THE CORE DOES WITH TIME, read out of the input rather than remembered: it STAMPS
# NOW and later ASKS HOW MANY MILLISECONDS HAVE PASSED.  That is the whole of it, at
# four places -- do_sleep's `done < msec` loop, vim_beep's 500 ms rate limit,
# handle_osc's `>= p_ost` timeout and inchar_loop's `wtime - elapsed_time` deadline --
# and NOT ONE of the four ever reads a field, prints a reading or compares two stamps
# for equality.  So the core never needs the LAYOUT of a clock, only a scalar.
#
# WHAT GOES, all of it phase 26's:
#
#   elapsed_T       8 mentions.  A core-owned TAGLESS `struct { long tv_sec; long
#                   tv_usec; }` -- phase 26's mirror of <sys/time.h>'s struct timeval,
#                   whose layout that phase had to static_assert equal.  The core
#                   stops modelling a host structure: the four objects become `long`.
#   elapsed()       6 mentions.  Its entire body is one clock read and a subtraction to
#                   milliseconds; with a scalar clock the subtraction is the caller's
#                   one operator and the function has nothing left to do.
#   musl_gettimeofday(long *, long *)
#                   7 mentions.  The host call phase 26 introduced, an out-parameter
#                   pair because a struct could not cross.  It becomes
#                   `long musl_now_ms(void)`: a value, not two stores.
#
# WHAT IT EARNS.  Read all thirteen core -> host signatures and the sentence is true:
# every one takes scalars and byte buffers only.  IT WAS ALREADY TRUE AT r27 -- phase 26
# chose `long *, long *` precisely so that `struct timeval` would not cross -- so this
# phase does not earn THAT sentence and the check does not claim it.  What it earns is
# the narrower one that was false until now: the core no longer DECLARES a type shaped
# like a libc struct, and its whole notion of time is one `long`.  `struct timeval`,
# `elapsed_T`, `elapsed` and `musl_gettimeofday` are all at 0 above the boundary
# afterwards; the host keeps its own `struct timeval`, for `select` and for the one
# `gettimeofday` call that is left in the file.
#
# WHAT `musl_now_ms()` RETURNS, AND IT IS A DECISION, NOT A DETAIL.  Milliseconds since
# a MONOTONIC ORIGIN the host chooses -- the whole second of its first call -- and not
# milliseconds since the epoch.  Every core use is a DIFFERENCE, so the origin is free,
# and the two choices are measured against each other in the check:
#
#   epoch      tv_sec * 1000 is ~1.79e12 today.  On a target where `long` is 64 bits
#              that is nothing; on one where it is 32 bits it overflows ON THE FIRST
#              CALL, every call, for ever -- signed overflow, so the standard gives no
#              value at all and -fwrapv gives a wrong one.  The clock is broken from
#              the moment the editor starts.
#   monotonic  (tv_sec - base) * 1000 overflows a 32-bit `long` after 2**31 ms, which
#              is 24.86 DAYS of editor uptime.  Until then every reading is exact.
#
# So the origin moves the 32-bit failure from "immediately" to "after 24.86 days", and
# it costs one branch and two statics IN THE HOST -- which is the part a new target
# rewrites anyway.  The base is LAZY rather than set in musl_host_init(), because an
# ordering dependency on another host function is exactly the kind of thing a host
# rewrite breaks silently, and the symptom would be base 0, epoch milliseconds and the
# overflow above.
#
# THE ORIGIN IS A WHOLE SECOND ON PURPOSE.  With `base` a second and no microsecond
# part, musl_now_ms() is epoch-milliseconds less the constant base*1000, so a
# DIFFERENCE of two readings is IDENTICAL under the two choices.  The origin is
# therefore behaviourally invisible, which is what lets the check measure the rounding
# ONCE instead of twice, and what lets it require the epoch variant's recording to be
# byte-identical to the product's.
#
# PRECISION IS NOT LOST AND THE ROUNDING POINT MOVES.  elapsed() subtracted and THEN
# divided: `(now.tv_sec - start.tv_sec) * 1000 + (now.tv_usec - start.tv_usec) / 1000`.
# musl_now_ms() divides at each reading and the caller subtracts.  Microseconds were
# already discarded either way -- the phase loses no precision the input had -- but the
# two roundings are not the same function, and MEASURED over 20,000,000 random pairs
# the difference is EXACTLY +-1 ms, both ways, never more, with the two formulas equally
# far from the true elapsed time (+0.4995 ms and +0.4996 ms mean).  The check runs that
# measurement rather than repeating it.  Whether a caller can SEE 1 ms is a separate
# question and the check answers it at each of the four.
set -eu

work=${1:?usage: zero28-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero28-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero28 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  clock        the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  clock        the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- EVERY substitution here changes code, so unlike phase 26 there is no tier 1 equality to fall back on and the recording answers for all of it"

# tools/phaserun.sh sweeps next, then runs pipes/zero28-check.sh.
