#!/bin/sh
# Whim phase 71 -- one buffer, structurally.  See WHIM-GOAL.md.
#
# Usage: pipes/whim71-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# THE INVARIANT IS ALREADY TRUE; this phase removes the machinery that pretended
# otherwise.  Phase 69 allowed at most one file argument, phase 70 made :e reuse the
# one buffer, and every buffer Ex command was retired long before that: all 24 rows
# -- :buffer :buffers :ls :files :bnext :bprevious :bNext :bfirst :blast :brewind
# :bmodified :bdelete :bunload :bwipeout :bufdo :ball :badd :balt -- already read
# ex_ni, and do_buffer, do_bufdel, ex_buffer, ex_bufdo and ex_listdo do not exist.
# So NOTHING can create a second buffer:
#
#   * win_alloc_first() at startup makes the one buffer, BEFORE command_line_scan;
#   * buflist_add() then names it through BLN_CURBUF, reusing that same buffer;
#   * do_ecmd() no longer calls buflist_new() at all (phase 70).
#
# THREE THINGS NAMED b_next ARE NOT THE BUFFER LIST, and a regex over the name would
# gut the editor:
#
#   * buffblock_T.b_next       -- the typeahead/redo chain: bh_first, redobuff,
#                                 old_redobuff, readbuf1, readbuf2.  ~30 sites.
#   * free_buffer()            -- buf->b_next = au_pending_free_buf, a free list.
#   * buf_T.b_next / b_prev    -- THIS is the buffer list, and only this.
#
# Every edit below is scoped with in_function() for exactly that reason.
#
# TWO SITES ARE NOT SIMPLE FOLDS:
#
#   * check_map_keycodes()'s walk is `for (bp = firstbuf; ; bp = bp->b_next)` with NO
#     termination test -- it runs once per buffer and then ONCE MORE with bp == NULL,
#     which is how the global (non buffer-local) maps get scanned, and breaks on that
#     pass.  It becomes `for (bp = curbuf; ; bp = NULL)`: still exactly two
#     iterations.  Folding it to a single pass would stop scanning half the maps.
#
#     This walk feeds add_termcap_entry(), NOT mapping lookup: a mapping is found
#     through curbuf->b_maphash[] directly, which never touches the buffer list and
#     was never at risk here.  Worth stating because the first version of this file
#     claimed otherwise.
#   * close_buffer()'s wipe branch is guarded by (b_prev != NULL || b_next != NULL),
#     which with a single buffer is ALREADY false.  The splice it guards is dead
#     today, not merely dead afterwards, so the guard folds to its else.
#
# WHAT IS LOST: nothing reachable.  buf_valid() becomes `buf == curbuf`, which makes
# set_curbuf()'s `enter_buffer(lastbuf)` fallback unreachable and takes the rest of
# set_curbuf's other-buffer handling with it.
#
# WHAT STAYS: buf_hashtab and buflist_findnr(), because five live callers still look
# a buffer up by number -- eval_vars, setmark_pos, check_changed_any, buflist_nr2name
# and buflist_getfile.  Collapsing that to a curbuf test is a separate step.
#
# THE DELTA: none expected.  The buffer commands are already ex_ni, so no exsweep row
# can move; declared empty and left for whimdelta.sh to correct.
set -eu

work=${1:?usage: whim71-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim71 "$f"

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim71-check.sh.
