#!/bin/sh
# Whim phase 7, the check -- the editor stops looking for files it was not given.
# See pipes/whim7-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim7-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim7-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim7-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim7-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"
