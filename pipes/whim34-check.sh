#!/bin/sh
# Whim phase 34, the check -- no abbreviations.
# See pipes/whim34-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim34-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim34-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim34-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim34-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The post-condition, after the sweep that takes them.
for g in check_abbr echeck_abbr ccheck_abbr ex_abbreviate ex_abclear; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  abbr         $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  abbr         nothing defines, lists or expands an abbreviation"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear colorscheme \
    abbreviate noreabbrev abclear iabbrev inoreabbrev iabclear cabbrev cnoreabbrev cabclear
