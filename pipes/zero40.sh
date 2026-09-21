#!/bin/sh
# Zero phase 40 -- the instrument learns to see the text layer.
#                  See ZERO-GOAL.md, ZERO-PLAN.md.
#
# Usage: pipes/zero40.sh <work-dir>      (run from the repository root)
#
# NO SOURCE CHANGE AT ALL: r40's zero-vim.c is its input's, byte for byte, and this
# phase asserts it first and last.  What changes is what every later phase is
# measured with.  This is zero phase 3's shape and zero phase 33's -- the two other
# phases that change no source and replace or repair an instrument -- and it is here
# for the same reason both of those were: a harness that cannot see a phase must be
# fixed BEFORE the phase, never after.
#
# WHAT WAS WRONG.  The editor holds its text in a memline: a memfile of 4,096-byte
# pages, a tree of pointer blocks over data blocks, with every pointer entry
# carrying the number of lines under it.  MEASURED with an instrumented build of
# the source this phase was handed: every one of ``zcases``'s 102 screen
# cases allocates EXACTLY ONE data block.  So the root pointer block holds exactly
# one entry for the whole session, `ml_find_line()` never chooses among entries --
# `idx` is 0 every time -- and `pe_line_count` is never the number that decides
# which child a line is in.  A `zero-vim` with
#
#     pp->pb_pointer[idx].pe_line_count--;
#
# deleted from `ml_find_line()`'s ML_DELETE arm therefore records all 102 cases
# BYTE FOR BYTE, and the Ex sweep, the argv records, the pty scenarios and the
# terminal table cannot see a text layer at all.  Forty phases had been verified by
# an instrument blind to the data structure the whole editor stands on.
#
# WHAT THE NEW PART IS.  ``zmemline``, the sixth part of a recording
# (`tools/zrecord.sh`): 16 cases that build buffers of 200 to 25,000 lines IN THE
# EDITOR -- there is no file argument (phase 5), no `:edit` (phase 8) and no
# `:read` (phase 7) -- churn them in the middle, and read them back.  Every line
# begins with its own line number, so a screen drawn with `'number'` shows the
# tree's answer beside the question; `zcompare.py` compares them under a `mem:`
# token beside `case:`.
#
# NOTHING HERE IS A NUMBER THAT WAS OBSERVED.  The page size, the data-block
# header, the pointer-entry size and `pb_count_max` are DERIVED by compiling the
# struct definitions out of the source the phase was handed; the line counts the
# corpus uses are read out of ``zmemline`` itself; and which case reaches
# which part of the tree is MEASURED with an instrumented build rather than
# intended.  A corpus that means to reach a root split and does not is exactly the
# defect this phase exists to end, so the phase is not allowed to assert it -- it
# has to show it.
#
# AND A MEMLINE RECORD CARRIES NO STREAM DIGEST, which is this phase's one
# departure from ``zcases``'s record and was forced by a measurement.  An
# undo in a buffer this size reports its age, and the editor writes the message and
# then positions the cursor to clear the rest of the line -- so `0 seconds ago`
# emits `\033[24;40H\033[K` and `1 second ago` emits `\033[24;39H\033[K`, a COLUMN
# derived from the width of a timestamp, which `tools/zrec.py`'s scrub cannot reach
# because it rewrites the age's TEXT and this is arithmetic on its length.  It was
# caught as a one-byte stream difference in `mem_undo_big`, once in 48 whole
# recordings of one binary, with every screen identical either way.  The digest is
# replaced by the count of `\033[?25h` -- where a redraw ends -- and what replaces
# it as evidence is section 6's clock control, which is stronger than a digest: it
# says the record does not depend on the clock AT ALL, rather than that two runs of
# it happened to agree.
#
# WHY RE-RECORDING THE BASELINES IS LEGITIMATE is zero phase 33's argument and is
# not repeated here: the baselines come from `whim-vim.c`, the pipeline's immutable
# input, built with WHIM's compile line, recorded three times and required
# identical, and nothing zero produces is on the recording side.  A new PART of a
# recording is a new file in that set, so phase 0 must record it:
#
#     rm -rf .reference/zero-baselines .cache/r0 && make zero-phase-0
#
# and `rm -rf .cache/r0` alone is not enough -- `pipes/zero0.sh` refuses a set that
# differs rather than overwriting it.
#
# WHAT THIS PHASE PROVES, in order, each depending on the one before:
#
#   1. the tree is untouched: zero-vim.c is what the phase was handed;
#   2. it builds with the boundary's flags, is still absolutely static, and `main`
#      is still the only external symbol;
#   3. THE CORPUS IS SIZED AGAINST THE SOURCE.  The block arithmetic is computed
#      from the struct definitions in the file, and the corpus's own smallest and
#      largest builds are required to clear the derived one-block and root-split
#      thresholds;
#   4. THE DEPTH IS REACHED, AND THE OLD CORPUS DOES NOT REACH IT.  One
#      instrumented build, seven markers on the seven paths, run under BOTH
#      corpora: every marker must be in at least one memline record and in NONE of
#      the 102.  That pair is the premise of the phase and its coverage in one
#      measurement;
#   5. THE INSTRUMENT IS DETERMINISTIC: three whole recordings of that binary, byte
#      for byte identical;
#   6. THE INSTRUMENT CAN FAIL, AND THE ONE IT JOINS CANNOT.  Five scratch builds.
#      Two corruptions of the tree's line bookkeeping -- one in the descent, one in
#      the deferred adjustment -- must move memline records and must move NONE of
#      the 102.  A third, in the descent CACHE, must move exactly the cases the
#      probe in section 4 says descend past one pointer level, which is a rule and
#      not a list.  A fourth must move NOTHING AT ALL although it reshapes the tree
#      completely, so that the corpus is shown to record BEHAVIOUR and not tree
#      shape.  And the fifth is about the RECORD and not the editor: both clocks
#      the core can read are replaced by counters that run away from the wall, and
#      no memline record may move -- while some of the 102 must, which is what
#      keeps that from being a control with no effect;
#   7. the declared delta holds -- NOTHING, and nothing new: tools/zerodelta.sh
#      --phase 40 against .reference/zero-baselines.

# THE BODY IS GO: tools/go/internal/check/zero40.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/st.sh
#   tools/zerodelta.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero40.sh <work-dir>}
exec tools/st.sh check zero40 "$work"
