#!/bin/sh
# Whim phase 8, the check -- :! keeps its name and loses its process.
# See pipes/whim8-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim8-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim8-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim8-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim8-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# This is the first whim phase whose point is the SYMBOL count, so it is
# checked rather than reported.  A phase that shrank the source while leaving
# the surface where it was would have cut in the wrong place, which is exactly
# the mistake this one exists to avoid.
tools/phasecheck.sh "$work" "$f" "$state/symbols"
if [ "$(cat .cache/symbols/last/after)" -ge "$(cat .cache/symbols/last/before)" ]; then
    echo "  symbols      this phase must lower the count"
    exit 1
fi

tools/phasebuild.sh "$work" "$before_lines"
