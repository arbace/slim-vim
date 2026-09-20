#!/bin/sh
# Zero phase 34 -- the core stops reallocating.
# See ZERO-PLAN.md 4c, whose transpilation rule is this phase's justification.
#
# Usage: pipes/zero34-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# THERE IS NO `musl_realloc` TO VENDOR, AND THAT IS THE WHOLE REASON THIS PHASE IS A
# REWRITE AND NOT A VENDORING.  Phases 14 and 15 gave the core its own definitions of
# sixteen mem*/str* functions and of qsort/bsearch, because each of those is a function
# of its arguments.  `realloc` is NOT: to move the old contents it must know how many
# bytes the old block held, and its interface -- `void *realloc(void *p, usize n)` --
# does not carry that number.  musl reads it back out of the chunk header two words
# below `p`, which is a fact about musl's heap and not about C.  So a core-owned
# `musl_realloc(void *p, usize n)` written over `malloc`, a copy and `free` CANNOT BE
# WRITTEN AT ALL: there is nothing to give the copy for a length.
#
# The only route left is to rewrite each call site with the size IT knows, and the
# phase exists because both core sites know it.  ZERO-PLAN.md 4c's rule -- the core is
# optimised for transpilation, so its meaning must be on the page -- is what makes that
# worth doing: on a JVM there is no `realloc`, and `malloc` + a copy + `free` is an
# array allocation and an arraycopy, which is exactly what these two sites now say.
#
# THREE CALL SITES, AND ONLY TWO OF THEM ARE THE CORE'S.  Every count is re-measured
# from the input here, `grep -ow realloc` above and below the first `#include`:
#
#   ga_grow_inner()   the core's.  Its old size is on the NEXT LINE already --
#                     `old_len = (usize)gap->ga_itemsize * gap->ga_maxlen;`, which the
#                     function computes to zero the tail.  That IS the old allocation.
#   get_keystroke()   the core's.  Its old size is `buflen` BEFORE the `buflen += 100;`
#                     immediately above the call, and the rewrite saves it in `t_buflen`
#                     beside the `t_buf` the input already saves, rather than writing
#                     `buflen - 100` and asking a reader to do the arithmetic.
#   adjust_types()    THE HOST'S, below the boundary, in the formatter island phase 27
#                     moved down.  It is left exactly as it is, and `realloc` therefore
#                     STAYS in `nm -u` -- an equality this phase declares rather than a
#                     symbol it frees.  See the check.
#
# THE FOUR TRAPS, each of which would be a silent memory bug and not a failure.
#
#   1  `realloc(nullptr, n)` IS `malloc(n)`.  `ga_grow_inner` is called with
#      `gap->ga_data == nullptr` on a growarray's first grow, and MEASURED on a full
#      recording of the input that is 2,739 of its 4,289 calls -- the majority case,
#      not an edge.  The rewrite must not copy from null and must not free null, so the
#      copy and the free are inside `if (gap->ga_data != nullptr)`.  The guard is what
#      makes the rewrite FAITHFUL rather than merely similar, and the check measures
#      exactly how much it is worth: on THIS implementation, nothing -- see the check's
#      `c_noguard`, which is reported rather than hidden.
#
#   2  ON FAILURE `realloc` LEAVES THE OLD BLOCK VALID AND ALLOCATED.  Both sites rely
#      on it.  `ga_grow_inner` returns FAIL with `ga_data` untouched; `get_keystroke`
#      frees the old block itself, with `vim_free`.  So in `ga_grow_inner` the `return
#      FAIL` comes BEFORE anything is freed, and in `get_keystroke` the free of the old
#      block moves into an `else` and the existing `vim_free(t_buf)` stays exactly where
#      it was.  The success-path free is `free()` and NOT `vim_free()`: `vim_free` does
#      nothing while `really_exiting`, and `realloc` frees regardless.
#
#   3  `ga_grow_inner` ZEROES `new_len - old_len` BYTES AFTER THE COPY.  That statement
#      is not moved and not rewritten; the copy is inserted above it, so the order is
#      copy-then-zero as it was realloc-then-zero.
#
#   4  SHRINKING.  Neither site can ask for less than it has, and it is MEASURED, not
#      assumed.  `ga_grow_inner`'s only caller is `ga_grow`, which calls it only when
#      `gap->ga_maxlen - gap->ga_len < n`, and the three statements above the allocation
#      only raise `n` -- so `new_len > old_len` always.  The input's own
#      `musl_memset(pp + old_len, 0, new_len - old_len)` already asserts it, `new_len -
#      old_len` being unsigned.  An instrumented build of the input marks a shrink at 0
#      of 106 records.  `get_keystroke` does `buflen += 100` immediately above, so the
#      new size exceeds the old by exactly 100.  `musl_memcpy` therefore copies the old
#      size at both sites and no minimum is needed -- which the check states as the
#      reason rather than as an omission.
#
# THE PROTOTYPE GOES WITH THE LAST CORE CALL.  `void *realloc(void *p, usize n);` is one
# of the nine plain libc prototypes phase 26 wrote below the `usize` typedef and phase 27
# carried above the includes; with no core call left it declares nothing the core uses,
# and `adjust_types()` takes its declaration from <stdlib.h>, which is above it.  Eight
# prototypes remain.  Phases 31 and 35 also shrink this block, and the check computes
# the count from the input rather than stating it, so this phase composes with either.
set -eu

work=${1:?usage: zero34-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero34-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero34 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  realloc      the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  realloc      the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- the check drives BOTH through the same unit harness, because the failure modes here are memory bugs and a screen recording cannot see one"

# tools/phaserun.sh sweeps next, then runs pipes/zero34-check.sh.
