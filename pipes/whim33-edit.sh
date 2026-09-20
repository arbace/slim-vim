#!/bin/sh
# Whim phase 33 -- commands whose machinery has already gone.  See WHIM-GOAL.md.
#
# Usage: pipes/whim33-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Every one of these still had a handler, and every one refused or did nothing
# when run with a sensible argument -- measured one by one, in Ex mode, reading
# the message each left:
#
#   shell                  E319, no processes since phase 8
#   gui gvim               E25, no GUI in this build
#   cdo cfdo ldo lfdo      E319, no quickfix lists
#   vim9cmd                E319, no eval layer
#   endclass endinterface  Vim9 class keywords, invalid without the eval layer
#   endenum public static this
#   digraphs               E196, no digraphs in this build
#   redrawtabpanel         E1547, no tab panel
#   colorscheme            E185, no colour scheme to find: nothing is installed
#
# A command that only says no is a row pointing at a handler that exists to say
# no, so the row goes to ex_ni -- WHIM-GOAL.md rule 3, the table keeps its
# shape -- and the sweep takes the handlers nothing else uses.  `:!` is the one
# refusal kept, on purpose: `:!cmd`, `:r !cmd` and `:w !cmd` are how a user
# reaches for a process, and phase 8's answer to that is the sentence it prints.
#
# ex_listdo also serves :argdo, :bufdo, :windo and :tabdo, so it stays; its two
# tests for the quickfix commands can never be true once those rows point
# elsewhere, and they are folded rather than left asking.
#
# THE DELTA: colorscheme.  Run bare it reported the scheme in slim-vim and
# succeeded; it is not implemented now.  Every other row already failed, or is
# one the sweep skips because it hands over the terminal.
set -eu

work=${1:?usage: whim33-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- the rows ------------------------------------------------------------------
tools/st.sh retire "$f" shell gui gvim cdo cfdo ldo lfdo vim9cmd \
    endclass endinterface endenum public static this \
    digraphs redrawtabpanel colorscheme

# --- ex_listdo's questions about commands that no longer reach it ---------------
tools/st.sh edit whim33 "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim33-check.sh.
