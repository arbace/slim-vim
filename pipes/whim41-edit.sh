#!/bin/sh
# Whim phase 41 -- the buffer list is walked by :bnext and :bprevious alone.
# See WHIM-GOAL.md.
#
# Usage: pipes/whim41-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# The list stays: every file edited is a buffer on it, :bnext and :bprevious move
# through it, CTRL-^ goes to the alternate one, and quitting still asks about the
# changed ones.  Every other command on it goes -- fifteen rows:
#
#   buffer buffers files ls badd balt bdelete bunload bwipeout
#   bfirst brewind blast bmodified bNext bufdo
#
# :bNext is a row of its own, so :bN goes with it; :bp still reaches :bprevious.
# See `nobuflist` for what a row cannot remove.
#
# THE DELTA: the ten rows that succeeded run bare, read from the slim baseline.
# badd, balt, bmodified, bufdo and bunload already failed with no argument.
set -eu

work=${1:?usage: whim41-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh retire "$f" buffer buffers files ls badd balt bdelete bunload \
    bwipeout bfirst brewind blast bmodified bNext bufdo
tools/st.sh nobuflist "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim41-check.sh.
