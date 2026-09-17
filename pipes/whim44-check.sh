#!/bin/sh
# Whim phase 44, the check -- no filters, sorting or alignment.
# See pipes/whim44-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim44-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim44-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim44-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim44-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in ex_bang ex_sort ex_uniq ex_retab ex_align; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  filters      $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  filters      no :!, no sorting, no retab, no alignment; the ! key beeps"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"
