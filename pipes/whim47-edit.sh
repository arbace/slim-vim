#!/bin/sh
# Whim phase 47 -- no :startinsert, :startreplace, :startgreplace or :stopinsert.  See WHIM-GOAL.md.
#
# Usage: pipes/whim47-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Commands that entered or left Insert mode from a command line: i, R, gR and
# Esc are the keys for that, and stay.
#
# THE DELTA: the four rows, which succeeded run bare.
set -eu

work=${1:?usage: whim47-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh retire "$f" startinsert startreplace startgreplace stopinsert

# tools/phaserun.sh sweeps next, then runs pipes/whim47-check.sh.
