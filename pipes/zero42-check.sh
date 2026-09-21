#!/bin/sh
# Zero phase 42's proof -- the swap file's residue.  See pipes/zero42-edit.sh.
#
# Usage: pipes/zero42-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# THE DECLARED DELTA IS NOTHING AT ALL, AND IT IS TWO DIFFERENT KINDS AT ONCE.  Four
# zero phases have declared nothing before, for four different reasons (CLAUDE.md,
# *Verification tiers*), and this one phase is two of them in the same edit:
#
#   THE NEGATIVE-BLOCK HALF IS PHASE 9'S KIND -- code that COULD NOT RUN.  The chain the
#   edit computes says `negative` is FALSE at every call, so mf_trans_add() returns
#   before it does anything and ml_find_line()'s `bnum < 0` arm is unreachable.  A
#   recording cannot show that, because there is nothing to show; what shows it is an
#   INSTRUMENTED PAIR, and this check builds it rather than citing one.  Four markers, on
#   the four places a negative block number would be made, translated or followed, and a
#   control OF IDENTICAL SHAPE in ml_new_data(), which every buffer reaches.  Measured on
#   the input, over the 102 screen cases, the Ex sweep, the argv sweep and eight stress
#   sessions: the four fire in NONE and the control fires in nearly all.
#
#   THE BLOCK-ZERO HALF IS PHASE 12'S KIND -- code that RUNS and the instrument cannot
#   see.  ml_open() fills the header for every buffer in every session, and nothing ever
#   reads it back, so the corpus executes this code everywhere and is blind to it.  The
#   same instrumented build says so with its other three markers, which fire in almost
#   every record -- and the two full recordings are byte-identical anyway.  An empty
#   declaration means something different in each half, and the check says which is
#   which rather than letting one number stand for both.
#
# THE BINARY IS NOT BYTE-IDENTICAL and this phase does not pretend otherwise: code goes,
# a memline's block numbers move down by one, and a pointer-block entry gets smaller.  So
# tier 1 of CLAUDE.md's table is out of reach and the evidence is arranged in the shape
# that table's second half describes -- a byte-identical RECORDING with controls that
# move it.
#
# THE FANOUT CHANGES, AND THAT IS WHAT PHASE 40 IS FOR.  `pe_old_lnum` is a member of
# PTR_EN, so taking it makes each pointer-block entry smaller and MORE OF THEM FIT IN A
# PAGE.  The tree is therefore shaped differently after this phase and the root pointer
# block overflows LATER.  Not one of the 102 screen cases can see that: measured, a
# binary with ml_append_int()'s root test left at the OLD block number -- a real bug, the
# root not kept where ml_find_line() starts -- draws all 102 of them IDENTICALLY, and all
# four of the survey's own deep cases with them.
#
# THIS IS THE FIRST MEMLINE CHANGE SINCE ZERO PHASE 40, which added a corpus of buffers
# big enough to have a tree for exactly this reason, and that corpus is the only recorded
# thing that tells the two apart: section 7b.  It also NARROWS what phase 40 reaches, and
# the check asserts that as an inequality rather than as a count -- phase 40 sized its
# buffers from `sizeof(PTR_EN)`, and a phase that makes a pointer block hold MORE children
# can only move cases out of the root-splitting set, never into it.  Section 8 is then the
# direct proof, at sixty thousand lines, with an instrument on the branch itself.

# THE BODY IS GO: tools/go/internal/check/zero42.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/canon.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zerodelta.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero42-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero42-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero42 "$work" "$state"
