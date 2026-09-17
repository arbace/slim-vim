#!/bin/sh
# Whim phase 10, the check -- no tag stack.
# See pipes/whim10-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim10-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim10-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim10-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim10-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# An error is not a warning: ask gcc whether it succeeded before asking what it
# complained about, or a failed compile ends the phase with nothing to say.

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"
