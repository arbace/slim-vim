#!/bin/sh
# Whim phase 46 -- no :wall, :qall, :quitall, :wqall or :xall.  See WHIM-GOAL.md.
#
# Usage: pipes/whim46-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# With one window and one buffer they were :w, :q, :wq and :x under longer
# names.  :quitall is :qall's long spelling, the same handler, and goes with it.
# tools/exsweep.py quit every run with :qall!; it now asks the binary once and
# quits with :q! where :qall! is not there, which is the same thing here.
#
# THE DELTA: the five rows, which succeeded run bare.
set -eu

work=${1:?usage: whim46-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh retire "$f" wall qall quitall wqall xall

# tools/phaserun.sh sweeps next, then runs pipes/whim46-check.sh.
