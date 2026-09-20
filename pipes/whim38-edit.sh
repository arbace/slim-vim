#!/bin/sh
# Whim phase 38 -- the argument list is walked by :next and :previous alone.
# See WHIM-GOAL.md.
#
# Usage: pipes/whim38-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# The list stays: `vim a b c` fills it, :next and :previous move through it,
# `:next x y` replaces it, :drop sets it, and quitting still says how many files
# are left.  Every other command on it goes -- twenty-five rows:
#
#   args argglobal arglocal argadd argdelete argdedupe argedit
#   argument sargument  first sfirst rewind srewind  last slast
#   snext wnext  Next sNext sprevious wNext wprevious  all sall  argdo
#
# :Next is a row of its own, spelled apart from :previous, so :N goes with it;
# :prev still reaches :previous.  See `noarglist` for what a row cannot
# remove.
#
# THE DELTA: the sixteen rows that succeeded run bare, read from the slim
# baseline.  argdo, argedit, Next, sNext, snext, sprevious, wNext, wnext and
# wprevious already failed with no argument.
set -eu

work=${1:?usage: whim38-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh retire "$f" args argglobal arglocal argadd argdelete argdedupe \
    argedit argument sargument first sfirst rewind srewind last slast \
    snext wnext Next sNext sprevious wNext wprevious all sall argdo
tools/st.sh noarglist "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim38-check.sh.
