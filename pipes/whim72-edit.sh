#!/bin/sh
# Whim phase 72 -- one window, one tabpage, structurally.  See WHIM-GOAL.md.
#
# Usage: pipes/whim72-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# THE INVARIANT IS PROVABLE, not imposed -- the phase 68 shape rather than the
# phase 70 one.  Windows are created in exactly one place: win_alloc(NULL, FALSE)
# from win_alloc_firstwin(), whose only caller is win_alloc_first() at startup.
# alloc_tabpage() is called exactly once, from the same function, and curtab is set
# to it there.  :tabnew, :tabedit, :split, :new and the rest are already ex_ni, and
# aucmd_win went in phase 68.  So firstwin == lastwin == curwin and
# first_tabpage == curtab, always, and this phase deletes the traversal that
# pretended otherwise.
#
# TWO LAYERS, FOLDED AS A PAIR.  Nearly every tabpage walk immediately contains
#
#     for ((wp) = ((tp) == curtab) ? firstwin : (tp)->tp_firstwin; (wp); ...)
#
# so folding the outer walk to `tp = curtab` makes that ternary constant-fold to
# firstwin, and folding the inner one then gives curwin.  Cutting one layer without
# the other would leave half a traversal at every one of these sites.
#
# SEVEN BODIES ARE REWRITTEN, NOT FOLDED, and they were found BEFORE writing a line
# of this file rather than after three dry runs.  Folding a walk deletes its `for`
# header, and C binds break/continue to the nearest enclosing loop or switch -- brace
# depth has nothing to do with it.  In phase 71 getout() failed to compile that way,
# which is the cheap outcome, and buflist_findpat() COMPILED FINE AND CHANGED
# BEHAVIOUR.  So fold_walks() below audits every body it is about to fold and
# REFUSES if any break/continue would rebind:
#
#   aucmd_prepbuf        break   -- the walk searched for the window showing a buffer
#   can_unload_buffer    break   -- same search, for "is it on screen"
#   borrow_stl_vsep_hl   both    -- two walks; the whole function collapses
#   current_win_nr       break   -- counts to the window, so: 1
#   current_tab_nr       break   -- counts to the tabpage, so: 1
#   getout               both    -- a tabpage walk that re-seeds next_tp and breaks
#   create_windows       break   -- a rewind loop over w_next, twice
#
# THE TABPAGE-SWITCHING GROUP IS DEAD BEHIND ONE GATE.  goto_tabpage_tp()'s whole
# body is `if (tp != curtab && leave_tabpage(...) == OK)`, which with one tabpage is
# never true.  Folding that gate away orphans leave_tabpage, enter_tabpage,
# valid_tabpage and use_tabpage, and the sweep then removes them -- taking the last
# readers of tp_firstwin, tp_lastwin and tp_prevwin with them.  Nothing here deletes
# those functions by name; removing the one gate is what kills them.
#
# WHAT STAYS, deliberately:
#   * the FRAME layer -- topframe, frame_T, fr_next, fr_child, fr_parent.  One window
#     still has one frame, and new_frame()/topframe are load-bearing for sizing.
#     Cutting frames is its own phase.
#   * b_nwindows.  Tracing every write: = 1 at window creation, balanced ++/-- pairs
#     in enter_buffer and aucmd_restbuf, and -- in close_buffer when the window drops
#     the buffer.  It is genuinely 0 after that, so `<= 0` and `== 0` are live
#     "no longer displayed" tests.  An earlier plan folded all 20 sites to a constant
#     1; that would have broken buffer release silently.
#   * prevwin and w_id.  aucmd_prepbuf/aucmd_restbuf save and restore the window by
#     id, and the incsearch state compares curwin->w_id, so neither is list state.
#   * the `curwin == NULL` guards that were `firstwin == NULL` in shell_new_rows,
#     shell_new_columns, min_rows and min_rows_for_all_tabpages.  They exist because
#     a resize can arrive before win_alloc_first(), and proving that it cannot is not
#     this phase's job.
#
# THE DELTA: none expected.  Every window and tabpage Ex command is already ex_ni, so
# no exsweep row can move; declared empty and left for whimdelta.sh to correct.
set -eu

work=${1:?usage: whim72-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim72 "$f"

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim72-check.sh.
