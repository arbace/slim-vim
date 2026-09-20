#!/bin/sh
# Whim phase 75 -- no autocommands.  See WHIM-GOAL.md.
#
# Usage: pipes/whim75-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# PROVED BY ABSENCE, not inferred from the command table.  `first_autopat[NUM_EVENTS]
# = { NULL }` is the ONLY write to that array in the whole file -- every other mention
# reads it.  No autocommand pattern can ever be registered, so:
#
#   * apply_autocmds_group() is already `return FALSE;`
#   * apply_autocmds(), apply_autocmds_exarg() and apply_autocmds_retval() are
#     one-line wrappers onto it, so ALL ~74 dispatch sites are no-ops;
#   * has_cursormovedI/has_textchangedI/has_textchangedP each return
#     `first_autopat[...] != NULL`, i.e. always FALSE;
#   * au_cleanup, au_remove_pat, au_del_cmd and aubuflocal_remove walk a permanently
#     empty list.
#
# :autocmd, :augroup, :doautocmd, :doautoall and :noautocmd were already ex_ni, but
# that is the weaker argument; the array being write-once-to-NULL is the strong one.
#
# TWO SITES ARE REWRITTEN, NOT FOLDED, and both would have been silent damage:
#
#   * close_buffer() -- the label `aucmd_abort:` sits INSIDE the block guarded by
#     apply_autocmds(EVENT_BUFWINLEAVE, ...), and THREE gotos target it, two of them
#     from outside that block under `if (abort_if_last)`.  fold_never would delete
#     the label and orphan them.  This is the phase-71 break-rebinding hazard wearing
#     a label instead of a loop.  The abort arm is hoisted out and kept reachable.
#   * open_buffer() -- the aco block mixes the autocommand call with REAL work:
#     `curbuf->b_flags &= ~(BF_CHECK_RO | BF_NEVERLOADED)`.  Deleting it wholesale
#     would change behaviour.
#
# THE CLASSIFICATION WAS DONE BY HAND because a scan got two sites BACKWARDS.
# 7712 and 7741 read `if (!(did_cmd = apply_autocmds_exarg(...)))` -- negated with an
# embedded assignment -- so they are ALWAYS TRUE (fold_always), not always false.
# A `startswith("if (!apply_autocmds")` test misses the `!(var = ...)` shape, and
# folding them the other way would have deleted the branch that actually runs.
#
#   fold_never (condition always FALSE)   6327 6344 6416 6423 6768 27758 27768
#   fold_always (condition always TRUE)   6531 7712 7741
#   dies with its guard                   15497 15512 (has_textchanged*), 21638
#                                         (has_cmdundefined)
#   value consumed                        7725 (did_cmd), 18098 (ins_apply_autocmds
#                                         -> return FALSE), 86559 (drop the |= term)
#   bare statements                       60 lines, deleted
#
# WHAT GOES BY CASCADE: the EVENT_ enum (123 enumerators, 127 lines), event_tab
# (127 rows), event_nr2name, auto_next_pat, AutoPat, AutoCmd, AutoPatCmd_T,
# active_apc_list, first_autopat, last_autopat, au_need_clean, autocmd_blocked,
# aucmd_prepbuf, aucmd_restbuf and aco_save_T.  Nothing here deletes those by name.
#
# SCOPE NOTE: trigger_cmd_autocmd() comes out HERE rather than with the other empty
# functions, because its call sites pass EVENT_* constants that this phase removes.
# may_trigger_modechanged() takes no argument and waits for the combined phase.
#
# THE DELTA: none expected.  Nothing could fire an autocommand, so removing the
# dispatch cannot change what the editor does.  Declared empty, left for whimdelta.sh.
set -eu

work=${1:?usage: whim75-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim75 "$f"

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim75-check.sh.
