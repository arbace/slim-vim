#!/bin/sh
# Whim phase 13, the check -- the editor stops re-reading a file it has already read.
# See pipes/whim13-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim13-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim13-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim13-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim13-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
