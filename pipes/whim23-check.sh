#!/bin/sh
# Whim phase 23, the check -- no floating-point library.
# See pipes/whim23-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim23-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim23-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim23-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim23-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in 'ceil(' 'floor(' 'log10(' 'infinity_str' 'TYPE_FLOAT' 'typename_float'; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  libm         $g still has $n mentions after the sweep"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  libm         nothing calls a floating-point function"


tools/phasecheck.sh "$work" "$f" "$state/symbols"

for g in ceil floor log10; do
    if grep -qx -- "$g" .cache/symbols/last/undefined; then
        echo "  symbols      $g is still undefined in the object"
        exit 1
    fi
done
echo "  symbols      ceil, floor and log10 are gone from nm -u"

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
