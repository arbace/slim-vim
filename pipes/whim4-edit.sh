#!/bin/sh
# Whim phase 4 -- the binary's name stops choosing what it does.  See WHIM-GOAL.md.
#
# Usage: pipes/whim4-edit.sh <work-dir> <state-dir>       (run from the repository root)
#
# parse_command_name() reads argv[0] and picks a mode from it -- a leading `r`
# is restricted, `view` is read-only, `ex` is Ex mode.  That is a Unix
# INSTALLATION convention: you symlink rvim, view and ex at one binary and let
# the name decide.  An embedded editor is one file that was never installed and
# has no use for it.
#
# It is also the trap this repository has paid for more than once: a reference
# binary saved as `ref` runs restricted, where every shell-out fails; renaming
# the product to slim-vim needed a side-by-side check first; and every harness
# here stages the binary under test as `vim` for no reason except this function.
#
# NOTHING IS LOST, and `noargv0` checks that rather than asserting it: it
# refuses to run unless -Z, -R, -y, -e and -E all still select the modes the
# name could.  Keeping the options was the requirement; proving they are still
# there is what makes the removal safe.
#
# THE DELTA: none.  The harnesses stage the binary as `vim`, which selected
# plain vim mode before and selects it now, so nothing they record can move.
set -eu

work=${1:?usage: whim4-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry point --------------------------------------------------
tools/st.sh noargv0 "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim4-check.sh.
