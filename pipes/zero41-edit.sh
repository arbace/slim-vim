#!/bin/sh
# Zero phase 41 -- freeing is free.  ZERO-GOAL.md's charter bullet, "A GARBAGE
# COLLECTOR IS ASSUMED FROM HERE ON".
#
# Usage: pipes/zero41-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# `host_alloc` BECOMES A BUMP ALLOCATOR AND `host_free` RETURNS WITHOUT DOING ANYTHING.
# Phase 35 moved `malloc` and `free` across the boundary and wrote the two wrappers that
# forwarded to them; this phase changes what is behind those two names and nothing else.
# The charter's words: "No real collector is built: `host_alloc` becomes a bump allocator
# in the host with enough arena for the test suite and `host_free` returns without doing
# anything, which is a change entirely below the boundary and touches no core line."
#
# THE CLAIM IS "FREEING IS NOW FREE" AND NOT "THE CORE STOPPED FREEING".  Every
# `host_free` call the core makes is still there and still made; what it costs is a
# store of a parameter and a return.  Some later phase may delete the calls, and it
# will be able to, which is the point of doing this one first.
#
# WHAT THE CORPUS ASKED FOR, MEASURED AND NOT GUESSED.  The input source was built with
# a counter on host_alloc that totals every request, rounded as the allocator below
# rounds it, and dumped from host_exit() -- which every session reaches.  Over the whole
# of tools/zrecord.sh, 268 sessions in 122 records, the largest single session asked for
# 200,458,672 bytes, and two separate recordings gave that same number.  It is ONE case:
#
#   the heaviest memline case, mem_deep_jumps, 25,000 lines     200,458,672
#   the next three memline cases                    53,134,304 / 52,559,280 / 52,506,976
#   the heaviest of the 102 screen cases                          1,722,512
#   a buffer of 100,000 lines                                    12,862,224
#   a buffer of 300,000 lines           35,157,264   (~112 bytes a line, LINEAR)
#   200,000 characters into ONE line                         20,013,114,624 (QUADRATIC)
#
# THE ARENA COULD NOT HAVE BEEN SIZED BEFORE ZERO PHASE 40, and that is worth saying
# plainly rather than leaving in the manifest.  The heaviest of the 102 screen cases asks
# for 1,722,512 bytes and the heaviest of phase 40's 16 memline cases asks for 115 TIMES
# MORE.  A phase written one boundary earlier would have measured the 102, found 1.7 MB,
# and sized an arena from a corpus that provably cannot reach the text layer at all --
# which is the defect phase 40 exists to have ended, arriving one phase later in a shape
# nobody predicted.  A 64 MiB arena was in fact written here first and the recording
# refused it: `THE RECORDING MOVED, in 1 of 122 records: memline/mem_deep_jumps`, the case
# dying with `host arena exhausted: 67108864 bytes, 67058640 used, request 60263`.
#
# THE LAST ROW IS THE REASON A FIXED ARENA IS A STATEMENT ABOUT THE WORKLOAD AND NOT
# ABOUT THE EDITOR, and it is written here rather than discovered later.  With nothing
# freed, what an arena must hold is not the live data but the TRAFFIC, and this editor's
# traffic is quadratic in the length of a single line being typed: `+normal 200000ax`
# wants twenty gigabytes.  No fixed arena covers that, so the choice is not "how big is
# safe" but "which workloads are covered".
#
# THE SIZE IS 1 GiB AND THE FIRST ARGUMENT FOR IT WAS WRONG, WHICH IS RECORDED HERE
# BECAUSE THE MEASUREMENT THAT KILLED IT IS WORTH MORE THAN THE NUMBER.  This phase first
# chose 64 MiB and justified the ceiling by saying the abort path costs the arena times
# the harness's concurrency -- "64 MiB across 64 threads is 4 GiB on a 62 GiB machine".
# That is FALSE except for a runaway session.  An ordinary session's resident memory is
# its TRAFFIC, which the arena does not change; an untouched arena page costs nothing at
# all.  Measured: the same source at 64 MiB and at 1 GiB produces a byte-identical image,
# 772,872 either way, because .bss is NOBITS.  So the size buys exactly one thing -- how
# far a runaway goes before it dies loudly -- and costs exactly one thing, address space.
# At 1,073,741,824 bytes it is 5.36 times the measured high-water, which is what lets the
# check keep a four-times rule with no weakening to justify.
#
# THE ARENA COSTS NOTHING TO STORE, WHICH IS MEASURED TOO AND IS WHY IT CAN BE THIS
# GENEROUS.  It is a file-scope object with no initialiser, so it is `.bss`, which is
# `NOBITS`: the section header records a size and the file holds no bytes.  Measured on
# this pipeline's own compile line, `.bss` goes from 24,600 bytes to 67,133,528 and the
# IMAGE SHRINKS, 781,064 -> 772,872, because musl's allocator is no longer linked in.
#
# FOUR PARTS, AND THE LAST TWO ARE NOT OPTIONAL.
#
#   1  host_alloc   the arena, the offset, and an abort that NAMES the arena, what is
#                   used and the request that did not fit.  Not nullptr and not silent:
#                   lalloc()'s out-of-memory path would turn a wall into a message and
#                   carry on, and a phase whose declared delta is nothing must not have
#                   a way of quietly doing less.
#   2  host_free    `(void)p;`.
#   3  format_overflow_error()'s `free(argcopy)`     BELOW the boundary, and phase 35
#   4  adjust_types()'s `realloc(*ap_types, ...)`    left both deliberately.
#
# PARTS 3 AND 4 ARE WHAT MAKES THIS PHASE CORRECT RATHER THAN NEARLY CORRECT, and
# neither is in the core.  The formatter's private island -- the four functions phase 27
# moved BELOW the includes because they need `va_list` -- still called libc's `free` and
# libc's `realloc` directly, on pointers that came from `alloc_clear()`, which is to say
# from `host_alloc`.  Phase 35 saw them and left them, naming `free`'s one below-boundary
# mention as "format_overflow_error() below the boundary", and phase 34 saw the other and
# said in as many words that the remaining `realloc` "is the host's and is not this
# phase's".  Both were right while `host_alloc` WAS `malloc`: the two allocators were one
# allocator.  This phase is where they stop being one, and a `free()` or a `realloc()` of
# an arena pointer is undefined behaviour from the line below.  So they move here, and
# the realloc moves by phase 34's own rewrite -- allocate, copy, free -- with phase 34's
# own traps read off this site:
#
#     TRAP 1  `realloc(nullptr, n)` is `malloc(n)`.  Not reachable here: the null case is
#             the OTHER arm of the same `if`, which calls alloc_clear().
#     TRAP 2  on failure `realloc` leaves the old block valid and allocated.  The
#             `return FAIL` is above everything this edit adds, so it still does.
#     TRAP 3  `realloc` does not initialise what it grows, and this site does not expect
#             it to: the loop below fills `[*num_posarg, arg)` itself.  The copy takes
#             the `*num_posarg` entries that were there, the loop fills the rest, and the
#             contents are what they were.
#
# NEITHER IS REACHED BY THE CORPUS AND ONE CANNOT BE REACHED AT ALL, which is why the
# check owns a probe for them instead of a recording.  `format_overflow_error()` is
# called only when `get_unsigned_int`'s `overflow_err` is true, and that argument is
# `tvs != nullptr`, and `vim_vsnprintf_typval` has ONE caller in this file, passing
# nullptr -- so it is phase 9's and phase 17's kind, code no build of zero-vim can run.
# `adjust_types()` needs a positional format spec and no string literal in the file holds
# one, so it takes a runtime format to reach; the check reaches it with one.
#
# WHAT THIS PHASE DOES NOT DO, AND IT IS MEASURED RATHER THAN OVERLOOKED.  `malloc`,
# `free` and `realloc` were the only users of `<stdlib.h>`, and with them gone the
# directive is dead: the check builds the output without it and the binary is
# BYTE-IDENTICAL.  It stays.  ZERO-GOAL.md permits a phase to remove a directive and
# phase 13 is the precedent for declining -- it measured that removing three of them was
# free and wrote "the count stays 18" into its own program.  The eleven stay eleven here
# for the same reason: this phase's subject is the allocator, the removal is free
# whenever somebody asks for it, and a phase that changes two things cannot say which one
# a difference came from.
#
# THE CORE IS NOT TOUCHED, AND THE EDIT ASSERTS IT RATHER THAN CLAIMING IT.  The text
# above the first `#include` must be byte-identical in and out.  The check states the
# same thing the way the project states it -- `cmp` of `make editor.c`'s own cut.
#
# THE INPUT BINARY IS BUILT HERE with SOURCE_DATE_EPOCH=0, and the check records from it.
set -eu

work=${1:?usage: zero41-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero41-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero41 "$f" "$state"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  arena        the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  arena        the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- host_alloc stops calling malloc and host_free stops calling free, so the binary is NOT byte-identical and the evidence is a RECORDING, an instrument that measures the arena the corpus really asks for, and controls on the guard, on the bump and on the two rewrites below the boundary the corpus cannot reach"

# tools/phaserun.sh sweeps next, then runs pipes/zero41-check.sh.
