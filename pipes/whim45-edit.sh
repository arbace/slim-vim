#!/bin/sh
# Whim phase 45 -- no :drop.  See WHIM-GOAL.md.
#
# Usage: pipes/whim45-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# :drop edited a file by putting it on the argument list and going to its first
# entry.  With one window and one buffer it is :args plus :first, both gone.
# ex_drop() was the last caller of set_arglist() and ex_rewind(), and the sweep
# takes all three.
#
# THE DELTA: none.  :drop already failed with no argument.
set -eu

work=${1:?usage: whim45-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh retire "$f" drop

# tools/phaserun.sh sweeps next, then runs pipes/whim45-check.sh.
