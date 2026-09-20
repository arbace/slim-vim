#!/bin/sh
# Zero phase 42 -- the swap file's residue.  See ZERO-GOAL.md and ZERO-PLAN.md 4a.
#
# Usage: pipes/zero42-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# THE FILESYSTEM WENT AT PHASES 6 TO 10 AND THE SWAP FILE'S MACHINERY DID NOT.  memline
# and memfile still keep the bookkeeping of a file that is written to a disk: a header
# block with the editor's version and the buffer's name in it, a translation table for
# blocks that have not been written out yet, a dirtiness state machine, and a record of
# where each block's lines USED to be.  None of it can be reached and none of it is read.
#
# EVERY ONE OF THESE FOUR GROUPS IS INVISIBLE TO EVERY TOOL IN tools/, AND FOR ONE
# REASON: they are all WRITTEN.  tools/deadfields.py takes a field named nowhere outside
# its own type, and each of these is named; tools/deadsweep.py asks gcc, and gcc has no
# warning for a struct member nothing reads, for an enumerator that is only ever OR-ed
# into a word nothing tests, or for a file-scope object that is read and never assigned.
# Run against the input, deadfields.py reports 0 fields.  So this is an EDIT and not a
# sweep, and the division of labour is stated rather than hoped for: the edit takes
# everything that is written, and the check names what is left standing for the sweep and
# what the sweep then found.
#
#   1  BLOCK ZERO.  `struct block0` is the swap file's header.  Its fields -- the two
#      identifying bytes, the version string, the page size, the file name and the four
#      magic numbers -- are WRITTEN in ml_open() and ml_setflags() and READ NOWHERE, in
#      any build of zero-vim, and the edit proves that as a partition over every mention
#      of every one of them: a declaration, an assignment, or a call that copies INTO the
#      field.  Nothing may yield a value.  The field list is read out of the struct rather
#      than typed here, because zero phase 36 already took `b0_pid` and a typed list would
#      be a phase out of date.
#
#      THE TWO SURVIVING BLOCKS MOVE DOWN BY ONE.  ml_open() allocated block nr 0 for the
#      header, 1 for the root pointer block and 2 for the first data block, and with the
#      header gone the pointer block is 0 and the data block 1.  Five numbers say so, and
#      two of them are outside ml_open(): ml_find_line() starts its descent at the root,
#      and ml_append_int() recognises the root by its block number when a split reaches
#      the top of the tree and the root has to be kept where the reader starts.  The
#      check's controls are on those two.
#
#   2  NEGATIVE BLOCK NUMBERS.  mf_trans_add() returns before it does anything unless a
#      block number is negative, and a block number is negative only if mf_new() is called
#      with `negative` TRUE.  THE CHAIN IS COMPUTED HERE AND NOT ASSERTED FROM A SURVEY:
#      mf_new()'s callers pass FALSE or ml_new_data()'s own parameter; ml_new_data()'s
#      callers pass FALSE or `flags & ML_APPEND_NEW`; ML_APPEND_NEW is set only by
#      ml_append()'s `newfile`; and `newfile` is FALSE at every ml_append() call site in
#      the file.  So `negative` is FALSE at every reachable call, no block number is ever
#      negative, mf_trans_add() is a no-op, the translation table is always empty and
#      ml_find_line()'s `bnum < 0` arm is unreachable.  The phase removes the whole
#      island: two functions, three memfile fields, the parameter, and the two flags whose
#      only purpose was to choose between marking a block dirty and calling the no-op.
#
#   3  THE DIRTINESS, WRITE-ONLY IN ALL THREE OF ITS LAYERS.  `mf_dirty` is a three-valued
#      field with six writes and two reads, and EACH READ IS THE CONDITION OF AN `if`
#      WHOSE ONLY STATEMENT WRITES THE FIELD AGAIN -- so nothing outside the field ever
#      learns its value, which the edit checks structurally.  `BH_DIRTY` is set three
#      times and never tested: `bh_flags` is read in exactly one place and that read
#      tests BH_LOCKED.  And ML_LOCKED_DIRTY and ML_LOCKED_POS, the memline's own pair,
#      are read at exactly one place between them -- the two arguments mf_put() is about
#      to stop taking.  mf_put() becomes `mf_put(bhdr_T *hp)`, which clears BH_LOCKED and
#      is the whole of what it did that anything reads.
#
#   4  pe_old_lnum, AND THE TWO LOCALS THAT EXIST ONLY TO FEED IT.  Seven writes, no read.
#      Four of the seven are the only statement of an `if`, and the two variables those
#      `if`s test are computed by a fourteen-line branch and used nowhere else -- so once
#      the field goes, gcc says `-Wunused-but-set-variable` for both, which
#      tools/deadsweep.py does not act on (CLAUDE.md, *Audit for dead code*).  The same is
#      true of ml_find_line()'s `dirty`, which was mf_put()'s third argument.  All three
#      are therefore the edit's.
#
#      AND mf_dont_release, WHICH IS A CONSTANT.  `static int mf_dont_release = FALSE;`,
#      read twice and ASSIGNED NOWHERE IN THE FILE.  No warning gcc emits covers a
#      file-scope object in either direction, so nothing here has ever been able to see
#      it.
#
# THE FANOUT CHANGES AND THAT IS NOT A BEHAVIOUR.  `pe_old_lnum` is a member of PTR_EN,
# the pointer-block entry, so taking it makes each entry smaller and more of them fit in
# a page.  The tree the editor builds for a given buffer is therefore shaped differently
# after this phase, which is a representation and not an observable -- and the check does
# not leave that to be believed: it drives both binaries to sixty thousand lines, where
# an instrumented build says the root pointer block really does overflow and the
# root-preserving branch really does run, and requires the two to draw the same screen.
#
# WHAT THIS PHASE DOES NOT TAKE.  `BH_LOCKED` looks like BH_DIRTY's twin and is not: it
# is read, by mf_put()'s `e_block_was_not_locked` assertion.  Measured -- a binary whose
# mf_put() SETS the bit instead of clearing it draws exactly the same 102 screen cases,
# because the only reader is an internal-error test that then never fires -- so it is
# unreachable EVIDENCE and not unreachable code, and the bit stays.
#
# THE INPUT BINARY IS BUILT HERE with SOURCE_DATE_EPOCH=0, and the check records from it.
# The edit also leaves its own output in $state/edit.c, so the check can state what the
# EDIT removed and what the SWEEP removed separately rather than as one number.
set -eu

work=${1:?usage: zero42-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero42-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero42 "$f" "$state"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  swapres      the input did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  swapres      the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from, and $state/edit.c is the text this edit hands to the sweep.  Code is removed and the block numbers of a memline move, so the binary is NOT byte-identical and this phase cannot use tier 1 of CLAUDE.md's verification table: the evidence is two recordings, an instrumented pair for each half, and a stress corpus deep enough to split the root"
