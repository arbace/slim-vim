#!/bin/sh
# Zero phase 43 -- a block number becomes a reference.
#
# Usage: pipes/zero43-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# THE MEMLINE STOPS NAMING ITS BLOCKS BY NUMBER AND HOLDS THEM.  `pe_bnum` and
# `ip_bnum` become `bhdr_T *`, `memline_T` gains `ml_root`, and `mf_get(mfp, nr,
# page_count)` becomes `mf_get(mfp, hp)`.  The hash table that turned an integer block
# number into a page then has nothing left to look up, so it goes -- with the free list
# it was keyed alongside, with `mf_blocknr_max` that handed the numbers out, and with
# `pe_page_count`, whose one reader was the argument `mf_get` no longer takes.
#
# THIS IS THE PHASE THAT BUYS THE PORT THE MOST, AND IT IS WORTH SAYING WHY IN ONE
# SENTENCE: an integer key into a side hash table becomes an object reference, which is
# the one thing a JVM has and C does not make it say.  ZERO-PLAN.md 4d lists what a port
# would have to be told about rather than translate, and the memline page is the whole
# of the list; this removes the outer half of it -- the indirection BETWEEN pages.  It
# does NOT remove the inner half: `db_index[1]` indexed to the line count, the fourteen
# `(char_u *)dp + start` interior pointers and the page arithmetic are untouched and are
# phase 44's.  A reference to a block whose innards are still a byte array is halfway.
#
# WHAT WAS THERE.  `mf_new()` handed every block an integer from a counter, inserted it
# in `mf_hash` under that integer, and the tree stored the integer; `mf_get()` took the
# integer back and hashed it to the page.  Nothing had been written to a disk since zero
# phase 6 and nothing could be read from one since phase 9, so the hash had held every
# live block for thirty-four phases and a lookup could not miss.  Four measurements say
# that in the text rather than as a story, and they are this edit's first act:
#
#   * every block `mf_new()` makes is inserted in the hash, and the only thing that ever
#     removes one is `mf_free()`, which removes it from the used list in the same breath;
#   * `mf_get()`'s two ways of failing are `nr >= mf_blocknr_max || nr < 0` and a miss,
#     and no caller passes anything but a number the tree stored;
#   * the used list is not an ordering anything reads.  `mf_used_last` is WRITE-ONLY
#     here -- phase 42 took `ml_setflags()`, its last reader -- and there is no release
#     path left to walk it: `mf_release_all` is WHIM'S, three mentions in `slim-vim.c`
#     and none in `whim-vim.c`, and phase 42 showed `mf_dont_release` to be a constant.
#     So moving a block to the head of the list is bookkeeping nothing observes, and
#     this edit keeps it anyway;
#   * `pe_page_count` is read ONCE, into the argument `mf_get()` is about to lose.
#
# SO THE HASH IS A MAP FROM A NUMBER THIS FILE INVENTS TO A POINTER IT ALREADY HAD.
#
# WHAT A WRITE-ONLY FIELD COSTS, AND WHY FOUR OF THEM ARE IN THE EDIT.  tools/sweep.sh
# finds a function nothing calls, a type nothing names and a field named nowhere outside
# its own type; it finds none of `mf_used_last`, `bh_page_count`, `pe_page_count` or
# `pe_bnum`, because every one of them is WRITTEN.  tools/deadfields.py reports 0 fields
# in this region for exactly that reason, and gcc has no warning for a struct member in
# either direction.  Phase 20's trap is the other half of it: remove a member and leave
# its initialiser and the compile says `excess elements in struct initializer`, which is
# a correct phase failing.  Every field here goes WITH its writes, in this edit, and
# every mention of every one of them is partitioned below by the function it sits in --
# a partition and not a count, because a count is a bet on the phase before this one.
#
# THE ONE STRING THIS PHASE CHANGES, SAID HERE AND NOT BURIED.  `E323: Line count wrong
# in block %ld` is the only message in the file that printed a block number, and there
# is no number left to print.  It becomes `E323: Line count wrong in block`.  It is an
# `iemsg` on the arm of `ml_find_line()` that runs when the line counts under a pointer
# block do not add up to the tree's own line count -- an integrity check, reachable only
# from a corrupt tree -- and the check measures that no record in a whole recording
# reaches it, on the binary this phase was handed, and exhibits both messages from a
# build that forces the arm.  `E298: Didn't get block nr 0?` and `E298: Didn't get block
# nr 1?` are not changed but DELETED, with the two tests that were the only thing that
# could raise them: ml_open() asked whether the first two blocks came back numbered 0
# and 1, and the question has no meaning once there are no numbers.  Both strings are
# left standing for tools/sweep.sh, which is where an unreferenced object belongs.
#
# THE ROOT IS THE ONE BLOCK THE TREE CANNOT REACH BY DESCENT, so it needs a name.
# `ml_open()` used to rely on the first block it made being number 0 and `ml_find_line()`
# started every descent at 0; `ml_append_int()` asked `mhi_key != 0` to know whether the
# block that had just overflowed was the root.  `memline_T.ml_root` is that fact written
# down, set once in `ml_open()` and never again -- the root block's IDENTITY does not
# change when the root splits, which is what makes one field enough: the split copies the
# root's contents into a NEW block and leaves the root holding one entry that points at
# it, so `ml_root` is still the root and the stack entry above it is still right.
set -eu

work=${1:?usage: zero43-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero43-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are the boundary makefile's and are not written here a second time
# (ZERO-GOAL.md rule 8).  The check needs the binary this phase was HANDED, for the
# instrumented pair and for the two recordings, so it is built here and left in the
# state directory (tools/phaserun.sh: what passes between the parts is files).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero43 "$f" "$state"

# NOT create_cmdidxs --check, for pipes/zero2-edit.sh's reason: the derived
# first-two-letters index went with the command table whim's phase 80 reduced, and the
# tool raises rather than reporting nothing.  Nothing here touches the command table.
#
# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  refblocks    the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  refblocks    the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside $state/old.c.  Every block in the tree is reached differently, so the binary is NOT byte-identical and this phase cannot use tier 1 of CLAUDE.md's verification table: the evidence is two whole recordings -- including the sixteen memline cases zero phase 40 added, which are the only part of any zero recording that asks the TREE a question -- an instrumented pair for the one message it changes, and controls that move what it must not"

# tools/phaserun.sh sweeps next, then runs pipes/zero43-check.sh.
