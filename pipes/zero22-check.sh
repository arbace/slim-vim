#!/bin/sh
# Zero phase 22, the check -- the variadic collapse.
# See pipes/zero22-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero22-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero22-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with the boundary's own flags.
#
# WHAT IS CLAIMED, in four parts:
#
#   STRUCTURE   `va_start` appears EXACTLY ONCE, and in `vim_snprintf`.  That is the
#               whole product of the phase and it is asserted as a count plus an owner
#               test, which is three lines and needs no tool.  Seven names at 0
#               mentions, five helpers at their measured counts, `vim_snprintf` moved by
#               exactly the arithmetic of the edit.
#   WARNINGS    `-Wformat=2` gives THE IDENTICAL 115 `-Wformat-nonliteral` warnings IN
#               THE IDENTICAL 53 FUNCTIONS before and after.  This is the strongest
#               cheap check available and the one a mangled expansion would fail while
#               the build did not: the format-checking attribute moves from the wrapper
#               to `vim_snprintf`, and it only lands on the same expressions if every
#               argument list came out right.
#   SYMBOLS     `nm -u` is THE SAME SET, asserted as a `comm` that is empty in BOTH
#               directions.  It is 18 names here and 17 in the boundary's own binary,
#               because tools/phasecheck.sh compiles plain -O0 and so adds
#               __stack_chk_fail, which the -fno-stack-protector build does not have --
#               and that is why the assertion is the equality and not the number.  A
#               reader meeting a 129-site phase expects a symbol to fall and none can:
#               a pure restructure inside one translation unit frees nothing.  The
#               binary GROWS, which is the same fact wearing its other face, and the
#               check reports the number rather than letting it look like a mistake.
#   BEHAVIOUR   the declared delta is NOTHING AT ALL, so tools/zerodelta.sh proves the
#               recording did not move.  And the recording is NEARLY BLIND to this
#               phase, which is measured rather than asserted (see below), so the phase
#               owes probes: 263 of them on both binaries, and FOUR DELIBERATE BREAKS
#               that say what the probes can and cannot see.
#
# HOW BLIND THE RECORDING IS -- MEASURED, with the input source built again with
# `write(2, "ZW|<wrapper>|<format>\n", ...)` at the entry to each of the seven.  Across
# the 102 screen cases: `vim_snprintf_safelen` 617 entries, `smsg_attr_keep` 6,
# `vim_snprintf_add` 2, and `smsg` 0, `smsg_attr` 0, `semsg` 0, `siemsg` 0.  `semsg` IS
# 94 OF THE 129 SITES AND THE SCREEN CORPUS ENTERS IT NOT ONCE.  That is the whole
# argument for probes.  The 263 below enter `semsg` 232 times over 34 distinct formats.
#
# THE FOUR BREAKS, AND TWO OF THEM MOVE NOTHING ON PURPOSE.  Each is this phase's own
# output with one thing wrong, built and run against the input binary:
#
#   b1  both room helpers return 20 instead of IOSIZE            129 of 263 differ
#   b2  the wrong tail -- every `semsg` site reports as an        155 of 263 differ
#       ordinary message instead of an error
#   b3  `safelen_result`'s clamp reduced to `return str_l;`         0 of 263 differ
#   b4  all three guards removed                                    0 of 263 differ
#
# b3 AND b4 ARE KEPT AT ZERO RATHER THAN DROPPED.  They are the honest statement of what
# the evidence cannot reach: the clamp needs a message longer than 1,025 bytes out of
# `fileinfo`, and the guards need `IObuff == NULL` (an out-of-memory failure of the
# first two allocations the process makes) or a `semsg` under `emsg_off > 0` whose
# scribble on `IObuff` somebody then reads.  Reporting them as 0 is the difference
# between "the probes prove the guards are load-bearing" -- which would be false -- and
# "the guards are correct by construction and the probes say so about b1 and b2".
#
# WHAT THE CHECK DELIBERATELY DOES NOT ASSERT: `vim_snprintf`'s mention count BEFORE the
# edit.  Phase 21 formats its host message with `vim_snprintf`, so that number is the
# message layer's and moves under it; this phase asserts the count AFTER, as the
# transformer's own arithmetic against whatever it was handed.

# THE BODY IS GO: tools/go/internal/check/zero22.go and tools/go/internal/check/zero22probes.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/enumvals.sh
#   tools/phasecheck.sh
#   tools/st.sh
set -eu

work=${1:?usage: zero22-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero22-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero22 "$work" "$state"
