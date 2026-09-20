#!/bin/sh
# Zero phase 26 -- the header types and macros the core can own.
# See ZERO-PLAN.md 4c, ZERO-GOAL.md, and .claude/briefs/zero-reorg.md 1 and 7.
#
# Usage: pipes/zero26-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# ZERO-PLAN.md 4c's design is that the FIRST `#include` becomes the boundary: the core
# is the prefix above it and has no preprocessor syntax at all.  That is phase 27's
# move.  This phase is the part of it that can be done BEFORE the move, and doing it
# before is the whole point -- see THE ORDERING below.
#
# WHAT THE CORE STILL TAKES FROM A HEADER, and what it gets instead.  Every count is
# `grep -ow` above the host block and every one is re-measured from the input here:
#
#   time_t          6   ->  `typedef long time_T;` and `time_T` at the other five.
#                           The core chooses the width, as phase 23 made it choose
#                           usize's.  What PINS the choice is the `time` prototype
#                           below: `long time(long *)` is accepted against <time.h>
#                           only where `time_t` IS `long`.
#   sig_atomic_t    2   ->  spelled `volatile int`, and the name disappears.  The
#                           THREE in the host block keep it: they are below the
#                           boundary and <signal.h> is theirs.
#   uintptr_t       1   ->  `usize`.  One cast, `(unsigned long long)(uintptr_t)p`.
#   struct timeval  4   ->  a core-owned TAGLESS struct with two `long` fields, and
#                           `musl_gettimeofday(long *sec, long *usec)` in the host
#                           block for the five calls.  This is the ONE item that
#                           changes code; see THE CLOCK.
#   MIN 7 / MAX 16  ->      expanded at 19 lines to the text <sys/param.h> gives,
#                           READ FROM THE HEADER rather than written here.
#   offsetof        9   ->  `__builtin_offsetof`, which ZERO-PLAN.md 4c settled.
#   ten libc calls  ->      plain prototypes: malloc realloc free time getpid kill
#                           write labs abs -- nine, `gettimeofday` being the tenth and
#                           the one that cannot stay, its argument being a struct.
#
# THE DERIVED CONSTANTS ARE NOT THIS PHASE'S.  `enum : int { INT_MAX = ... };` placed
# after `#include <limits.h>` is `enum : int { 0x7fffffff = ... };`, a syntax error, so
# the twelve constants LONG_MAX INT_MAX PATH_MAX ULLONG_MAX LLONG_MAX INT_MIN SIGHUP
# SIGTERM LONG_MIN LLONG_MIN SIZE_MAX EXIT_FAILURE can only be written once the
# includes have moved.  They belong to phase 27 with the move, and they are the only
# header-supplied names this phase leaves in the core.
#
# THE ORDERING -- WHY THIS IS A PHASE OF ITS OWN AND WHY IT COMES FIRST.  Every
# declaration here REPLACES something a header above it still supplies, so the ordinary
# build cross-checks every one of them for free, and after the move there is nothing
# left to check against.  MEASURED, four ways, each a control in the check:
#
#   `int time(int *tp);`            error: conflicting types for 'time'
#   `void *malloc(int n);`          error: conflicting types for 'malloc'
#   `long getpid(void);`            error: conflicting types for 'getpid'
#   `static void *malloc(usize n);` error: static declaration of 'malloc' follows
#                                   non-static declaration
#
# THE LAST IS THE TRAP THE BRIEF NAMES, AND THE ORDERING CHANGES ITS SHAPE.  After the
# move a `static` prototype is a LINK failure -- gcc says `'malloc' used but never
# defined` -- because there is no other declaration to conflict with.  Here it is a
# hard error at the declaration itself, which is cheaper and points at the line.
#
# AND THE POSITIVE FORM IS WHAT THE MOVE DESTROYS.  Fifteen `static_assert`s compare
# every core-owned spelling against the header type it replaces -- `_Generic((time_T)0,
# time_t: ...)`, `_Generic((usize)0, uintptr_t: ...)`, `sizeof(elapsed_T) ==
# sizeof(struct timeval)`, `__builtin_offsetof(T, m) == offsetof(T, m)` at all six
# types -- and every one of them names a header type, so not one can be written once
# the headers are below.  They are a control in the check, not in the product.
#
# THE TAG IS STILL FORBIDDEN, AND THE REASON IN THE BRIEF IS NO LONGER TRUE.  The brief
# says a core-defined `struct timeval` tag is a hard `error: redefinition`.  MEASURED
# here: it is NOT, under the dialect this file compiles in.  C23 permits a struct to be
# redeclared with the same members, and gcc 15 takes it in silence both ways round --
# `-std=c11` and `-std=c17` give `error: redefinition of 'struct timeval'` and `-std=c23`
# gives nothing.  So the tagless struct is mandatory for a better reason than a
# diagnostic: the core must not define a libc TAG at all, and the layout equality has to
# be ASSERTED rather than left to an error C23 has removed.  The check does both --
# the tag control under c11 and under the file's own dialect, and the three
# `static_assert`s on the layout.
#
# THE CLOCK IS THE ONLY THING THAT CHANGES CODE, and the check proves that as an
# equality rather than claiming it.  Everything above is a rename or a macro expansion
# that the preprocessor was already performing, so it cannot generate a different
# instruction; `gettimeofday(&start_tv, nullptr)` becoming
# `musl_gettimeofday(&start_tv.tv_sec, &start_tv.tv_usec)` at five sites can and does.
# MEASURED: with the clock alone reverted, the binary is `cmp`-IDENTICAL to the one
# this phase was handed -- 788,488 bytes -- so the other six items and the nine
# prototypes are tier 1 of CLAUDE.md's verification table, and the clock is the only
# thing a recording has to answer for.  It does: MEASURED, the two recordings are
# BYTE-IDENTICAL, and the recording is NOT blind to the clock -- `musl_gettimeofday`
# writing the two fields the wrong way round moves SEVEN records.
#
# WHERE `musl_gettimeofday` GOES, AND IT IS NOT A FREE CHOICE.  It is defined inside
# the host block, immediately above `musl_delay`, because ``zhostonly`` reads
# the host region as the lines from `host_winch_pending` to the last brace of
# `musl_suspend()` and requires every mention of `struct timeval` to be inside it.  A
# definition below `musl_suspend` would be outside the region and the tool would refuse.
set -eu

work=${1:?usage: zero26-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero26-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

# MIN and MAX ARE READ FROM THE HEADER, not written here.  Two macro calls with
# distinctive arguments go through the preprocessor and come back as the expansion the
# header actually defines; the edit turns that into its template by replacing the two
# arguments.  If <sys/param.h> ever spelled MIN differently this phase would expand it
# differently, which is the only honest meaning of "the exact text the header gives".
printf '#include <sys/param.h>\nMIN(ZZA,ZZB)\nMAX(ZZA,ZZB)\n' > "$state/minmax-probe.c"
grep ZZA <"$state/minmax-probe.c" >/dev/null
gcc -E -P "$state/minmax-probe.c" | grep ZZA > "$state/minmax.txt"
test "$(wc -l <"$state/minmax.txt")" = 2

tools/st.sh edit zero26 "$f" "$state/minmax.txt"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  headers      the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  headers      the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- the clock is the only item that changes code, so the check reverts IT alone and requires THE SAME BYTES back, and the recording answers for the clock"

# tools/phaserun.sh sweeps next, then runs pipes/zero26-check.sh.
