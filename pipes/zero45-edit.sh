#!/bin/sh
# Zero phase 45 -- fold the node types.  See ZERO-GOAL.md.
#
# Usage: pipes/zero45-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# THE MEMFILE GOES, AND WITH IT THE LAST THING BETWEEN THE TREE AND ITS NODES.
# Until this phase a memline node is TWO allocations: a `bhdr_T` of four members --
# two list pointers, a `char_u *bh_data` and a lock flag -- and, hanging off it, a
# 4,096-byte PAGE that is cast to `PTR_BL *` or `DATA_BL *` depending on the two-byte
# id at its front.  A `memfile_T` of two members owns the list head and the page size.
# After this phase
#
#     struct block_hdr    { short_u bh_id; };
#     struct pointer_block{ bhdr_T pb_hdr; short_u pb_count; PTR_EN pb_pointer[PB_COUNT_MAX]; };
#     struct data_block   { bhdr_T db_hdr; linenr_T db_line_count; DATA_LN db_line[DB_LINE_MAX]; };
#
# and a node is ONE allocation AT ITS OWN SIZE: 1,040 bytes for a leaf and 4,088 for a
# branch, against 4,128 for either of them before.  `bhdr_T` is the node's tag and the
# first member of both, so `(PTR_BL *)hp` and `(bhdr_T *)pp` are the same address and
# the file needs no union; `memfile_T` has nothing left to hold and is gone; and the
# question "does this buffer have a memline" is `ml_root` where it was `ml_mfp`.
#
# THIS IS THE THING ZERO PHASE 44 NAMED AND DECLINED, in its own words: "Allocating a
# block at its own size means giving memfile a byte size where it has a page count ...
# It is named here so it is not lost: it would take the leaf from 112 bytes a line to
# 64, and it would MAKE AN OFF-BY-ONE IN THE CAPACITY BOUND VISIBLE, which today it is
# not."  Both halves are measured by the check rather than repeated: the leaf's node
# cost falls from 64.5 bytes a line to 16.25, and phase 44's own `cap` control -- the
# leaf capacity test widened by one -- moves 0 of 118 records on the input and 4 of 118
# here, in one run, with the input's binary built from the source beside it.
#
# WHAT THE FANOUT DOES, WHICH IS THE ONE THING THIS PHASE COULD HAVE DESTROYED.
# `pb_count_max` was computed per block as
# `(mf_page_size - offsetof(PTR_BL, pb_pointer)) / sizeof(PTR_EN)`, which is
# (4096 - 8) / 16 = 255, and it is the tree's fanout.  Zero phase 40's corpus reaches a
# ROOT SPLIT in exactly one of its sixteen cases, `mem_deep_jumps`, because that case
# builds 391 data blocks and 391 > 255; the other fifteen and all 102 screen cases
# reach none of it.  A phase that took `sizeof(PTR_EN)` to 8 would put the fanout at
# 511, and 391 < 511 would take root-split coverage to ZERO -- silently, because the
# instrument would still run and still pass.  So:
#
#   * PTR_EN IS NOT TOUCHED.  It is `{bhdr_T *pe_block; linenr_T pe_line_count;}` here
#     exactly as it was there, 16 bytes either side -- and a `static_assert` says so
#     rather than leaving it to be rediscovered.
#   * THE NEW STRUCT HAS THE SAME OFFSET.  `bhdr_T` is two bytes and `pb_count` two,
#     so `pb_pointer` starts at 8 as it did when `pb_id`, `pb_count` and
#     `pb_count_max` were three shorts.  PB_COUNT_MAX = 255 is therefore the number the
#     input computes and not a number chosen, and the second `static_assert` states it
#     that way: `PB_COUNT_MAX == (4096 - 8) / sizeof(PTR_EN)`, which FAILS TO COMPILE
#     if a later phase narrows the entry.
#
# The check measures the consequence and not just the arithmetic: the five markers of
# zero phase 40's instrument, on this phase's output and on its input in the same run,
# case by case.  And a control builds this phase's output with PB_COUNT_MAX = 511 and
# reports what it costs -- 0 of 118 records move and MLSPLITPTR, MLSPLITROOT and MLDEEP
# go 1 -> 0, which is the hazard demonstrated rather than described.
#
# WHAT GOES, MEASURED ON THE INPUT AND ASSERTED AS A PARTITION AND NOT AS A COUNT
# (below, `classify`).  Every mention of every one of these is in file scope, in one of
# the ten `mf_*` functions, in one of the eleven memline functions, or -- for `ml_mfp`
# alone -- in one of the seven places outside the memline that ask whether a buffer has
# one.  A mention anywhere else is a rule this edit does not have, and it refuses.
#
#   bh_next bh_prev       15 mentions   the used list, whose one consumer was mf_close
#   bh_data               24            the page hanging off the header
#   bh_flags               5            the lock: nothing can evict a block
#   mf_used_first          6            the list head
#   mf_page_size           6            the page size, read in four places
#   memfile memfile_T     27            the type and its tag
#   ml_mfp                25            the handle, and the "is it open" question
#   pb_id db_id            9            two tags where the node has one
#   pb_count_max           3            a field written once and read once
#   MEMFILE_PAGE_SIZE      3
#   the ten mf_* names    47            mf_open mf_close mf_new mf_get mf_put mf_free
#                                       mf_ins_used mf_rem_used mf_alloc_bhdr mf_free_bhdr
#   mfp                   55            no function holds a handle on a memfile
#   page_count page_size   8
#
# AND WHAT THE SWEEP TAKES, STATED HERE AS THE OTHER HALF OF THE SAME PARTITION, which
# is zero phase 43's form: `BH_LOCKED`, whose only three readers were mf_new, mf_get and
# mf_put, and `e_block_was_not_locked`, the E293 mf_put raised.  The edit leaves each at
# exactly ONE mention -- its own definition -- and the check requires the sweep to take
# both to zero and to take NOTHING ELSE.
#
# NOTHING IS FREED THAT WAS NOT FREED BEFORE, and the lifetime rule is unchanged.
# `mf_close()` walked the used list at ml_close() and freed every block on it, and the
# used list was exactly the set of live nodes -- so `ml_free_tree()` walks the TREE
# instead and frees the same set.  It is recursive and the depth is the tree's height,
# which is 3 on the heaviest case the corpus has.  `mf_free()`'s two call sites in
# ml_delete_int() become `vim_free(hp)`, one allocation where there were two.  A control
# measures that removing both is invisible, for the reason ZERO-GOAL.md's charter gives:
# host_free() returns without doing anything.
#
# THE ZEROING IS KEPT AND IT IS LOAD-BEARING ONCE.  mf_new() memset the page to 0 and
# the two constructors call alloc_clear() instead, which is the same act.  It matters in
# exactly one place: ml_open()'s error path runs ml_free_tree() over a root whose single
# pointer entry has not been filled in yet, and a zeroed `pe_block` is the nullptr that
# walk stops on.  A control measures that the host's arena happens to hand out zeroed
# memory anyway -- which is a fact about the host and not a promise to the core.
#
# HOW THE EDIT IS WRITTEN.  Every region is found by the function it is in and by its
# own first and last line; every local the fold stops using is removed by COMPUTING that
# its name is left mentioned once in its own function, never by listing it; and the two
# id constants are carried as they are found rather than spelled, because `(('p' << 8) +
# 't')` is zero phase 9's macro expansion and not this phase's text.  No line number is
# pinned and no line this phase does not itself replace is quoted.
set -eu

work=${1:?usage: zero45-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero45-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero45 "$f" "$state"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  node         the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  node         the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: this phase changes how every block is allocated and reached, and owes two recordings that do not move"

# tools/phaserun.sh sweeps next, then runs pipes/zero45-check.sh.
