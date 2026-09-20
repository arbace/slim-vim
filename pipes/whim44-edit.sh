#!/bin/sh
# Whim phase 44 -- no filters, sorting or alignment.  See WHIM-GOAL.md.
#
# Usage: pipes/whim44-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Seven rows go to ex_ni: :! (and :{range}!), :sort, :uniq, :retab, :left,
# :center and :right.  :! was kept in Phase 8 on purpose, as the sentence it
# printed; it is dropped here on request.  The `!` operator key built nothing but
# a :{range}! command line, so its row points at nv_error.  :r !cmd and :w !cmd
# reach do_bang() through :read and :write, not through the :! row, and keep
# Phase 8's refusal: with their ! not special, :w !cmd would write a file of
# that name.
#
# THE DELTA: the six rows that succeeded run bare -- :sort, :uniq, :retab, :left,
# :center, :right -- and the behaviour cases that used them: retab, sort_u and
# sort_n.  :! already differed from Phase 8.
set -eu

work=${1:?usage: whim44-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh retire "$f" '!' sort uniq retab left center right
tools/st.sh edit whim44 "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim44-check.sh.
