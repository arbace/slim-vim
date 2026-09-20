#!/bin/sh
# Whim phase 68 -- one window, structurally.  See WHIM-GOAL.md.
#
# Usage: pipes/whim68-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# THE INVARIANT THIS ESTABLISHES, and then spends:
#
#   A window is created in exactly two places -- win_alloc_firstwin(), once at
#   startup, and win_split_ins(), whose ONLY caller is aucmd_prepbuf().  win_split(),
#   make_windows() and win_new_tabpage() have no mentions at all.  A tabpage is
#   created once, by alloc_tabpage() in win_alloc_first().  So remove the
#   autocommand window and nothing can add a window or a tabpage ever again:
#
#       firstwin == lastwin  and  first_tabpage->tp_next == NULL
#
#   one_window(), last_window() and only_one_window() are then constant TRUE, and
#   every caller folds.  That is not a guess about the harness -- it is what the
#   two creation sites allow.
#
# WHY THE AUTOCOMMAND WINDOW CAN GO.  aucmd_prepbuf() splits one open only when no
# window shows the buffer, in order to run autocommands there -- and
# apply_autocmds_group() has been `return FALSE` since the phase that removed
# autocommands.  The window would be built to run nothing.
#
# WHAT WAS ALREADY A NO-OP, which is why this removes capability from the source
# and none from the editor:
#
#   win_close() tests last_window() first and answers "cannot close last window",
#       so the calls in ex_quit(), ex_exit() and do_exedit() could never close
#       anything.  ex_quit() and ex_exit() reach getout(0) before them anyway.
#   do_exedit()'s call is guarded by old_curwin != NULL, and its one caller passes
#       NULL.
#   close_windows() loops `wp != NULL && !(firstwin == lastwin)`, false at once,
#       and then over tabpages other than curtab, of which there are none.
#
# WHAT STAYS, because it is not about having two windows: win_comp_pos() and
# last_status() are reached from shell_new_rows() and did_set_laststatus(), so a
# terminal resize and :set laststatus still compute the one window's geometry.
# The frame code does not vanish wholesale, and the probes check that.
#
# THE DELTA: none.  No key, command or option changes.
set -eu

work=${1:?usage: whim68-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim68 "$f"

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim68-check.sh.
