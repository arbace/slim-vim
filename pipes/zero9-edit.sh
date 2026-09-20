#!/bin/sh
# Zero phase 9 -- nothing reads a byte.
# See ZERO-GOAL.md.
#
# Usage: pipes/zero9-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Phases 6, 7 and 8 took every way to ASK for a file: the six commands that put
# bytes on a disk, the one that takes them off it, and the five that point the
# editor at another one.  What was left of reading a file is the machinery under
# those commands -- `readfile()`, 787 lines, and the two arms of `open_buffer()`
# that call it.  This phase takes those arms, and the sweep takes the machinery.
#
# READFILE() WAS ALREADY UNREACHABLE WHEN THIS PHASE WAS HANDED THE TREE, and that
# is the whole of what makes the phase delicate rather than difficult.  Its three
# call sites are one in `read_buffer()` and two in `open_buffer()`, and
# `read_buffer`'s only callers are those same two arms; the outer arm needs
# `curbuf->b_ffname != NULL` and the inner one needs a `read_stdin` argument that,
# since phase 5 removed the file argument and the bare `-`, all four callers pass
# as FALSE.  So no input this editor can be given reaches it, and gcc keeps it only
# because it cannot prove `b_ffname != NULL` never holds.  The difference this
# phase makes is between code that cannot run and code that is not there -- and
# because it IS that, no behavioural probe can see it.  pipes/zero9-check.sh says
# what stands in for one: the input source built twice, instrumented.
#
# FOUR ANCHORS, ALL INSIDE open_buffer(), and everything else is the sweep's
# (ZERO-GOAL.md rule 1: removal is computed, not listed).  Sixteen functions go
# without one of them being named here.
#
#   1. the `if (curbuf->b_ffname != NULL) {...} else if (read_stdin) {...}` pair,
#      as exact text with the blank line after it.  That is the entire cut: the two
#      arms hold all three calls into the read path.
#   2. `int read_fifo = FALSE;` -- set nowhere once anchor 1 has gone, read twice.
#   3. `else if (retval == OK && !read_stdin && !read_fifo)` -> `else if (retval ==
#      OK)`, which is where anchor 2's second reader was.
#   4. the signature: `open_buffer(int read_stdin, exarg_T *eap, int flags_arg)` ->
#      `open_buffer(void)`, the `int flags = flags_arg;` local, and the four call
#      sites, every one of which already passes `FALSE, NULL, 0`.
#
# ANCHOR 4 IS WHAT TAKES read_stdin TO ZERO, and it is measured rather than argued.
# Without it `open_buffer` keeps three parameters that nothing reads, and THE SWEEP
# CANNOT SEE THEM: tools/sweep.sh compiles with `-Wno-unused-parameter`, so an
# unused parameter is invisible where an unused local is not -- measured, anchors
# 1-3 alone leave the `int flags = flags_arg;` local deleted by the sweep's own
# unused-variable pass and `read_stdin` alive at exactly ONE mention, the parameter
# nothing reads.  Both swept files are 82,572 lines and differ in exactly five
# lines -- the signature and the four calls -- and THE TWO RECORDINGS ARE
# BYTE-IDENTICAL, as are the two binaries' sizes.  So the fold costs nothing, says
# what is true, and is taken.
#
# THERE IS NO PROTOTYPE FOR open_buffer.  It is defined above its first call, so
# the `static int open_buffer(...)` line the proto block would hold does not exist
# and a phase that edits one fails loudly.  Anchor 4 edits the definition alone.
#
# THE FURTHER FOLD IS DECLINED, DELIBERATELY.  After anchor 1, `retval` in
# `open_buffer` is `OK` from its initialiser to its return and nothing between can
# change it, so `if (retval != OK) return retval;` is dead, the function could be
# `void`, and the two `open_buffer() == FAIL` guards in the `ml_*` layer can never
# hold.  That is memline tidy and not the read path; this phase asserts `retval` at
# its 5 mentions and says it is constant, and leaves the fold to a later one.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, exactly as pipes/zero2-edit.sh and zero4- through zero8-edit.sh do it, and
# the source goes with it as $state/old.c.  The check needs BOTH: the binary is the
# left-hand side of every "this did not move" comparison, and the source is what it
# builds twice more, instrumented, for the only evidence this phase has.
set -eu

work=${1:?usage: zero9-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero9-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero9 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  nobyte       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  nobyte       the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: no recording can see this phase, so the check builds that source twice more with readfile() and open_buffer() instrumented"

# tools/phaserun.sh sweeps next, then runs pipes/zero9-check.sh.
