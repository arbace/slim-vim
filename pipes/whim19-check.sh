#!/bin/sh
# Whim phase 19, the check -- the terminal is what the build says.
# See pipes/whim19-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim19-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim19-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim19-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim19-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The post-condition: after the sweep, no config path, no option and no
# environment name this phase removed is mentioned anywhere.  Asking before the
# sweep gets the wrong answer -- process_env is still there at that point and it
# is the sweep that removes it.
for g in 'getenv((char \*)((char_u \*)"TERM")' 'getenv("LINES")' 'getenv("COLUMNS")' 'getenv((char \*)((char_u \*)"COLORS")'; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  globals      $g still has $n mentions after the sweep"
        echo "               a dropped row leaves its global uninitialised, and a"
        echo "               reader of it is a segfault before the first keystroke"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  terminal     nothing asks the environment what terminal this is"


tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
