#!/bin/sh
# Whim phase 73 -- one frame.  See WHIM-GOAL.md.
#
# Usage: pipes/whim73-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# THE STRONGEST INVARIANT OF THIS RUN, and it is proved by absence rather than by
# argument: GREPPING THE WHOLE FILE FOR A WRITE TO fr_child, fr_next, fr_prev OR
# fr_parent RETURNS NOTHING AT ALL.  The frame tree is never linked.
#
#   * alloc_clear(sizeof(frame_T)) appears exactly once, in new_frame(), whose only
#     caller is win_alloc_firstwin() -- itself called once, from win_alloc_first();
#   * new_frame() writes fr_layout = FR_LEAF and fr_win = wp, and nothing else ever
#     writes fr_layout;
#   * win_alloc_firstwin() sets topframe = curwin->w_frame;
#   * there is no frame_insert, frame_append, frame_remove, win_split or
#     win_split_ins anywhere -- they went with the window layout in phase 68/72.
#
# So topframe == curwin->w_frame, fr_layout is FR_LEAF forever, and fr_child,
# fr_next, fr_prev and fr_parent are permanently NULL.  Every FR_ROW and FR_COL
# branch is dead, every fr_child walk iterates zero times, and every fr_parent walk
# terminates on its first test.  This phase is therefore a set of BODY REPLACEMENTS,
# not a fold campaign: each function keeps the arm that runs and loses the arms that
# cannot.
#
# THE BREAK HAZARD IS HANDLED BY CONSTRUCTION.  The audit named four loops whose
# break binds to the loop being removed -- stl_connected, frame_new_height,
# frame_new_width (twice) and command_height -- and all four are in the
# replace-whole-body set, so nothing is folded out from under a break.  That is the
# phase 71 lesson applied ahead of time rather than after three dry runs.
#
# WHAT IS NOT A CONSTANT, and must keep its arithmetic:
#   * frame_minheight() reads p_wh, p_wmh and w_status_height.  min_rows() and
#     did_set_cmdheight()'s clamp depend on the number it returns, so the leaf arm
#     stays exactly as it is; only the recursion goes.  Replacing it with a literal
#     would silently change what :set cmdheight= accepts.
#   * fr_width and fr_height on the one frame are live layout state, read by
#     win_do_lines, screen_ins_lines, screen_del_lines, redraw_block, screen_line,
#     win_line and did_set_cmdheight.  The FIELDS stay; only the tree goes.
#
# WHAT GOES BY CASCADE: frame_fixed_height and frame_fixed_width reach `return FALSE`
# and their callers' `wfh`/`wfw` loops vanish, so the sweep removes them.  The FR_ROW
# and FR_COL enumerators lose every reader.  Nothing here deletes those by name.
#
# THE DELTA: none expected.  Every window-splitting and resizing Ex command is
# already ex_ni, and :set cmdheight= keeps the same accepted range because
# frame_minheight keeps its arithmetic.  Declared empty, left for whimdelta.sh.
set -eu

work=${1:?usage: whim73-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim73 "$f"

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim73-check.sh.
