#!/bin/sh
# Whim phase 4, the check -- the binary's name stops choosing what it does.
# See pipes/whim4-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim4-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim4-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim4-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim4-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"
