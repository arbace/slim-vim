#!/bin/sh
# Whim phase 16, the check -- six options that no longer decide anything.
# See pipes/whim16-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim16-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim16-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim16-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim16-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The post-condition, and the check that was missing when this phase first ran.
# dropoptions.py --strict asks "does anything still read this global?", but it
# has to ask BEFORE the sweep, when the option's own callback still does.  After
# the sweep the question is answerable and the answer must be nothing at all --
# an unread global is itself swept, so the right count is zero mentions, not one.
for g in p_path p_sua p_tags p_tc p_ar p_swf; do
    n=$(grep -c "\b$g\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  globals      $g still has $n mentions after the sweep"
        echo "               a dropped row leaves its global uninitialised, and a"
        echo "               reader of it is a segfault before the first keystroke"
        grep -n "\b$g\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  globals      none of the six is mentioned anywhere any more"


tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
