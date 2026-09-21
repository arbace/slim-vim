#!/bin/sh
# Zero phase 28, the check -- the scalar clock.
# See pipes/zero28-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero28-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero28-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# WHAT IS CLAIMED, in eight parts:
#
#   ARITHMETIC  computed FROM THE INPUT: elapsed_T, elapsed, now_tv and
#               musl_gettimeofday are at 0, `struct timeval` is 0 above the boundary
#               and 3 below it, musl_now_ms is 9 above and 1 below, and the line count
#               moved by exactly -16 in the core and +6 in the host.
#   THE BOUNDARY
#               `make editor.c`'s cut, computed here by the same awk clause: 0
#               directives, `-fsyntax-only` with no error and no warning that is not a
#               boundary name, and the warning set STATED AS A SET -- twelve
#               `musl_`/`host_` names and `vim_snprintf`, with musl_gettimeofday
#               REPLACED by musl_now_ms and not added to.
#   THE SHAPE   every one of the thirteen signatures takes scalars and byte buffers
#               only.  IT IS COMPUTED ON THE INPUT TOO, and the input satisfies it:
#               phase 26 chose `musl_gettimeofday(long *, long *)` precisely so that
#               `struct timeval` would not cross, so this phase does NOT earn that
#               sentence and must not claim it.  What it earns is stated below.
#   THE ROUNDING
#               MEASURED, not argued.  elapsed() subtracted and then divided;
#               musl_now_ms divides at each reading and the caller subtracts.  A probe
#               compiled and run here compares the two over 20,000,000 random pairs and
#               must find the difference bounded by EXACTLY 1 ms, in both directions,
#               with the two formulas equally far from the true elapsed time.
#   CANON       tools/canon.sh is a NO-OP on the output: the four `long` declarations,
#               the eight new statements and musl_now_ms are written the way this file
#               writes everything else.
#   HOST        `zhostonly`, whose vocabulary this phase EXTENDS: `gettimeofday`
#               is a host word from here, with the five core call sites phase 26 moved
#               named as exceptions at the counts they had at r20, r21 and r25.
#   SYMBOLS     `nm -u` is THE SAME SET -- 17 names, `comm` empty in both directions --
#               and `main` is still the only external symbol.  **`gettimeofday` DOES
#               NOT LEAVE**, and the check says so as an equality rather than letting a
#               reader expect a clock phase to free a clock symbol: the host still calls
#               it to implement musl_now_ms, and a symbol leaves when its last caller
#               leaves the FILE, which is the split and not this phase.
#   BEHAVIOUR   the declared delta is NOTHING AT ALL, and the 102 screen cases CANNOT
#               SEE THIS PHASE -- which is measured rather than assumed, and is why the
#               phase owes probes.  See below.
#
# THE SCREEN CORPUS IS BLIND TO THE CLOCK, AND THAT IS A MEASUREMENT.  Two full
# recordings being byte-identical would mean very little on its own here: of the 102
# cases, 95 ring the bell once and 7 not at all, and NOT ONE rings it twice -- so
# vim_beep's 500 ms rate limit is never exercised a second time and the only reading the
# corpus could see never happens.  Measured: a control whose clock NEVER ADVANCES, one
# that RUNS BACKWARDS and one that runs 1000x FAST all move 0 of the 102 cases.  Phase
# 26's control moved six, and it was not a clock control: swapping musl_gettimeofday's
# two output fields makes each reading an independent random number rather than a
# consistently wrong one, which is a different thing from a clock.
#
# SO THE PHASE OWES PROBES, and `gs` is what they are built on: `nv_g_cmd`'s `s` arm is
# `do_sleep(count * 1000)`, which is the ONE call site a keystroke file can drive and
# the one that makes real time pass inside the editor.  Four probes on the binary this
# phase was handed and on its own, required to agree:
#
#   1gs            ~1,010 ms   do_sleep's loop, measured against the wall clock
#   2gs            ~2,009 ms   and again at twice the length: the loop caps a wait at
#                              1,000 ms, so 2gs is TWO iterations and 1gs is one
#   hgshh          2 bells     vim_beep's threshold in BOTH directions in one probe:
#                              h at column 0 rings, gs lets a second pass, the next h
#                              rings because more than 500 ms have gone, and the third
#                              is suppressed because less than 500 have
#
# AND EACH HALF IS PROVEN ABLE TO FAIL, by a control aimed at THAT half:
#
#   fast    the clock runs 1000x fast.  `2gs` returns after ONE 1,000 ms wait instead
#           of two -- measured 1,008 ms against 2,009 -- so the difference `2gs - 1gs`
#           collapses from ~1,000 ms to ~0.  It terminates, which is why it is the
#           control the timing assertion uses.
#   froze   the clock never advances.  `do_sleep`'s `done` stays 0 and `1gs` NEVER
#           RETURNS -- the probe hits its timeout.
#   nobell  vim_beep's `> 500` written `> 500000`, so the second h cannot ring: 1 bell.
#   allbell     ... written `> -1`, so the third one can: 3 bells.
#           THE BELL CONTROLS MOVE THE THRESHOLD AND NOT THE CLOCK, and that is a
#           measurement about the probe rather than a preference.  A clock control that
#           breaks the rate limit breaks do_sleep FIRST -- `froze` and a backwards clock
#           were both tried, and `hgshh` blocks on each, so neither can say anything
#           about bells at all.
#   ceil    every reading rounded UP instead of down: `(tv_usec + 999) / 1000`.  This is
#           the ROUNDING question made into a control, and it perturbs every reading by
#           up to a full millisecond -- twice what the change from elapsed() can.  Its
#           probes are the product's and its FULL RECORDING is byte-identical, which is
#           the answer to "can any caller see one millisecond": no.
#
# AND ONE MORE THAT IS NOT A CONTROL BUT A DECISION.  `epoch` is musl_now_ms written the
# other way -- milliseconds since 1970 rather than since the whole second of its first
# call.  Its probes and its full recording are the product's, which is what makes the
# origin a free choice and not a behaviour change; the reason the product takes the
# monotonic one is 32-bit arithmetic, and pipes/zero28-edit.sh states it.

# THE BODY IS GO: tools/go/internal/check/zero28.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/canon.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero28-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero28-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero28 "$work" "$state"
