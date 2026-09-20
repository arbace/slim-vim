#!/bin/sh
# Whim phase 37 -- commands that do nothing, and three that do something unwanted.
# See WHIM-GOAL.md.
#
# Usage: pipes/whim37-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Read one by one in the handlers:
#
#   browse confirm         modifiers whose flags went with the dialogs; each
#                          skipped its own name and ran the rest
#   tmap tnoremap tunmap   mappings for terminal-job mode, which nothing enters
#   tmapclear
#   winpos                 "not implemented" bare, and checked two numbers and
#                          did nothing with them otherwise
#   behave                 set 'selection', 'selectmode' and 'keymodel' to
#                          another editor's habits, mswin's naming the mouse
#   mode                   a screen-mode switch no terminal here has
#   open                   vi's open mode, which is :visual after a cursor move
#
# THE DELTA: the rows that succeeded run bare -- browse, confirm, mode, open,
# tmap, tmapclear and tnoremap, read from the slim baseline.  behave, tunmap and
# winpos already failed with no argument.  :highlight stays: it is how the
# colour of 'hlsearch' is set.
set -eu

work=${1:?usage: whim37-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh retire "$f" browse confirm tmap tnoremap tunmap tmapclear \
    winpos behave mode open
tools/st.sh noinert "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim37-check.sh.
