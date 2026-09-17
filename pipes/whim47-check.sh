#!/bin/sh
# Whim phase 47, the check -- no :startinsert, :startreplace, :startgreplace or :stopinsert.
# See pipes/whim47-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim47-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim47-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim47-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim47-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in ex_startinsert ex_stopinsert; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  insertcmds   $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  insertcmds   no command enters or leaves Insert mode"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"
