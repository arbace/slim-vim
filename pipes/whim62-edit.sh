#!/bin/sh
# Whim phase 62 -- no buffer-type, file-type, listing, jump, update-time or autowrite options.  See WHIM-GOAL.md.
#
# Usage: pipes/whim62-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
#   'buflisted'     every reader chose which autocommand event to fire, and
#                   apply_autocmds_group() is `return FALSE` -- or searched a
#                   buffer list of one
#   'filetype'      every reader fed the FileType event, which cannot fire, or
#                   fix_help_buffer(), and :help is ex_ni
#   'buftype'       live only through :set bt=: nofile, nowrite, acwrite and prompt
#                   refused :w and skipped reading; help set b_help.  Nothing
#                   inside the editor ever set it.  bt_dontwrite(),
#                   bt_nofilename(), bt_nofileread() and bt_prompt() fold as false
#                   at every caller
#   'jumpoptions'   empty: the "stack" behaviour of the jump list folds away
#   'updatetime'    dead, though it looked live: after that long idle,
#                   inchar_loop() asked trigger_cursorhold(), which is `return
#                   FALSE`, and called before_blocking(), whose swap sync reaches
#                   an empty ml_sync_all() and whose terminal flush only acts
#                   inside a screen redraw, never at idle.  So the idle wait goes:
#                   a wait with no timeout blocks at once, and before_blocking(),
#                   updatescript() and ml_sync_all() go with the CursorHold probe
#   'autowrite'     off: autowrite() always failed and autowrite_all() returned,
#   'autowriteall'  so their callers and the CCGD_AW flag fold
#
# THE DELTA: none the harnesses record.  The probes check the seven are unknown
# and that :w still writes.
set -eu

work=${1:?usage: whim62-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim62 "$f"

tools/st.sh dropoptions "$f" jumpoptions updatetime autowrite autowriteall
tools/st.sh dropoptions "$f" --local buflisted buftype filetype

tools/sweep.sh "$f"
# 'buflisted' leaves too little plumbing for droplocal.py: buflist_new() was its
# initialiser, and the folds above took that.  What is left is the field and its
# get_varp() case, and they go by hand.
tools/st.sh edit whim62bl "$f"
tools/st.sh droplocal "$f" b_p_bt b_p_ft

# tools/phaserun.sh sweeps next, then runs pipes/whim62-check.sh.
