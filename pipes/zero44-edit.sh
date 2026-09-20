#!/bin/sh
# Zero phase 44 -- de-page the leaf.  See ZERO-GOAL.md.
#
# Usage: pipes/zero44-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# A DATA BLOCK STOPS BEING A PAGE OF BYTES AND BECOMES AN ARRAY OF LINE RECORDS.
# Until this phase a leaf of the memline tree is a header, an index of byte offsets
# growing UP from the header, and a text arena growing DOWN from the end of the
# page, with the two meeting at `db_free` bytes of gap.  A line's text lives inside
# the block, so inserting a line in the middle memmoves the arena and rewrites every
# index below it; a line that grows past the gap is appended-and-deleted into another
# block; and a line longer than a page makes the block two pages.  After this phase
# the leaf is
#
#     struct data_line { char_u *dl_text; colnr_T dl_len; char dl_marked; };
#     struct data_block { short_u db_id; linenr_T db_line_count;
#                         DATA_LN db_line[DB_LINE_MAX]; };
#
# and a line's text is its own allocation.  Inserting a line shifts records, not
# bytes; replacing a line stores a pointer.
#
# WHY IT IS CHEAP NOW AND WAS NOT BEFORE.  The arena exists for exactly one reason,
# to avoid a malloc per line, and ZERO-GOAL.md's charter has retired that reason: "A
# GARBAGE COLLECTOR IS ASSUMED FROM HERE ON".  Zero phase 41 made host_alloc a bump
# allocator and host_free a return, so a per-line allocation costs a pointer bump and
# freeing costs nothing.  This phase spends that.
#
# AND WHAT IT SPENDS IS MEASURED, by the check's own counter and on both sides:
# the heaviest memline session asks the host for 201,927,792 bytes where the input
# asks 200,438,864, +0.7%.  A leaf page per 64 lines costs about what a leaf page per
# 78 lines and its arena cost, and the per-line text is what the arena used to hold
# inside the page.  With nothing freed that figure is a session's TRAFFIC and not its
# live data, which is why it is two hundred megabytes and why zero phase 41's arena
# is a gigabyte -- a number that phase and this one arrived at from opposite ends
# with instruments written apart, agreeing to the byte.
#
# THE TARGET REPRESENTATION IS TODAY'S DIRTY-LINE PATH MADE PERMANENT, which is why
# the rewrite can be this small.  `buf->b_ml.ml_line_ptr` under ML_LINE_DIRTY is
# ALREADY a separately allocated `char_u *` with `ml_line_len` beside it -- that is
# what ml_replace_len() builds and what del_bytes() edits in place when
# ml_line_alloced() is true.  ml_flush_line()'s job was to copy that buffer back into
# the page; here it stores the pointer, and the sixty-line "does the new text still
# fit" branch under it -- the memmove, the index fixup and the append-then-delete
# fallback -- has nothing left to decide.
#
# WHAT GOES, EVERY ONE OF IT MEASURED ON THE INPUT AND ASSERTED AS A PARTITION AND
# NOT AS A COUNT (below, `classify`):
#
#   db_free           14 mentions      the gap, in bytes
#   db_txt_start      29               the arena's low water
#   db_txt_end         6               the arena's high water
#   db_index          34               the offset index, declared `unsigned [1]`
#   the top bit       17               DB_MARKED, stolen from an offset, now a field
#   (char_u *)dp +    14               every interior pointer into the page
#   offsetof(DATA_BL)  2               there is nothing left to measure
#   ML_APPEND_MARK     5               its one caller was the fallback that goes
#
# THE THIRD offsetof IS NOT THIS PHASE'S.  ml_new_ptr()'s
# `offsetof(PTR_BL, pb_pointer)` measures a POINTER block, which is still a page of
# entries and is not the leaf.  De-paging the branch is a phase of its own and would
# change the tree's fanout on purpose; this one leaves it alone and says so.
#
# DB_LINE_MAX IS A FREE PARAMETER NOW AND IT IS CHOSEN BY MEASUREMENT.  A leaf used
# to hold as many lines as fitted in a page -- 78 of `zmemline`'s 47-byte
# lines on the boundary this was first written against -- and nothing decides it any
# more, so the value is a tuning knob.  The corpus CANNOT SEE IT: measured,
# DB_LINE_MAX of 32, 64, 128 and even 1 all record the 102 screen cases and the 16
# memline cases byte for byte, so no argument from "the recording agrees" is worth
# anything here.  What it does decide is how much of the tree the corpus REACHES, and
# that is measured, with zero phase 40's own markers, ON THIS PHASE'S ACTUAL INPUT:
#
#     DB_LINE_MAX   SPLITDATA  SPLITPTR  SPLITROOT  IDXNZ  DEEP
#         32           16         5          5        16     5
#         64           16         1          1        16     1
#        128           16         0          0        16     0
#        255           14         0          0        14     0
#     r43, the input  16         1          1        16     1
#
# 64 IS TAKEN BECAUSE IT REACHES EXACTLY WHAT THE INPUT REACHES, and 255 -- the value
# that would fill the page -- is the one that must not be chosen: it reaches no
# pointer-block split at all, so the natural-looking choice, the one that wastes
# nothing, would blind the instrument on the very phase that rewrites the tree.
#
# THE MARGIN IS ONE CASE AND IT HAS BEEN NARROWING UNDER THIS PHASE, which is worth
# writing down rather than discovering.  The same table taken on r40 read 6/5/1/0 in
# the SPLITROOT column, so 128 was a live choice then and reaches ZERO now: zero
# phase 42 took `pe_old_lnum` out of PTR_EN and phase 43 took the block number and the
# page count, and pb_count_max has gone 127 -> 170 -> 255 while the corpus's buffer
# sizes have not moved.  Measured directly on r43: mem_deep_jumps makes 321 data
# blocks on the input and 391 here, against a pb_count_max of 255, and no other case
# reaches 255 on either side.  So a PTR_EN of 8 bytes would put pb_count_max at 511
# and take even 64 to zero -- at which point the corpus needs resizing or DB_LINE_MAX
# needs lowering (32 reaches 5), and that is the phase that shrinks PTR_EN to decide,
# not this one.
#
# THE LEAF IS STILL ALLOCATED AS ONE MEMFILE PAGE and that is deliberate scope.
# sizeof(DATA_BL) is 1,040 bytes of a 4,096-byte page, which the edit asserts with a
# static_assert rather than leaving to be discovered.  Allocating a block at its own
# size means giving memfile a byte size where it has a page count, which is block
# NUMBERING as well as block size -- the machinery zero phase 43 has just rewritten --
# and a phase that replaced the leaf's representation and changed how blocks are
# allocated in one act would have two claims and one set of evidence.  It is named
# here so it is not lost: it would take the leaf from 112 bytes a line to 64, and it
# would make an off-by-one in the capacity bound VISIBLE, which today it is not (the
# check measures that and reports it).  Two findings of the same neighbourhood go with
# it, and phase 43 has already taken one of them from the other side: `pe_page_count`
# and `bh_page_count` were constant 1 after this phase and are gone before it.
#
# NOTHING IS FREED, AND THAT IS THE LIFETIME RULE.  A record owns its text and never
# gives it back: ml_flush_line() stores the replacement and drops the old pointer,
# ml_delete_int() drops a record's, and neither calls vim_free().  So
#
#     A POINTER RETURNED BY ml_get*() IS VALID FOR THE LIFETIME OF THE PROCESS.
#
# which is strictly weaker than what 341 call sites needed before, where the pointer
# was into a page and any insert or delete in the same block, any flush of any line
# in it, and any split invalidated it.  The check states the rule as a partition over
# every assignment to `dl_text` in the output, and probes it with a build that
# poisons the text a record stops owning.
#
# HOW THE EDIT IS WRITTEN, because phases 42 and 43 rewrite the same functions.
# Nothing here is anchored to a line this phase does not itself replace: every region
# is found by the function it is in and by its own first and last line, every call
# whose arity changes is rewritten by DROPPING ITS LAST ARGUMENT rather than by
# matching the argument, every `ml_flags |=` statement inside a replaced region is
# carried forward as it was found, and every local that the rewrite stops using is
# removed by COMPUTING that its name is left mentioned once.  A phase that wrote
# `ML_LOCKED_DIRTY` out would break on phase 42, which removes it.
set -eu

work=${1:?usage: zero44-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero44-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero44 "$f" "$state"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  leaf         the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  leaf         the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: this phase rewrites the storage of every line and owes two recordings that do not move"

# tools/phaserun.sh sweeps next, then runs pipes/zero44-check.sh.
