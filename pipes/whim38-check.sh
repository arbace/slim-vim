#!/bin/sh
# Whim phase 38, the check -- the argument list is walked by :next and :previous alone.
# See pipes/whim38-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim38-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim38-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim38-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim38-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in ex_args ex_argadd ex_argdelete ex_argdedupe ex_argedit ex_argument \
         ex_last ex_wnext ex_all get_arglist_name; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  arglist      $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
for g in ex_next ex_previous do_argfile ex_rewind; do
    if ! grep -qE -- "\\b$g\\b" "$f"; then
        echo "  arglist      $g is gone, and :next, :previous or :drop needed it"
        exit 1
    fi
done
echo "  arglist      :next, :previous and :drop walk the list; nothing else does"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"
