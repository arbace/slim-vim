#!/bin/sh
# Whim phase 36, the check -- one tab page, always.
# See pipes/whim36-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim36-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim36-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim36-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim36-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The post-condition, after the sweeps that take them.
for g in ex_tabclose ex_tabnext ex_tabmove ex_tabonly ex_tabs ex_redrawtabline \
         goto_tabpage goto_tabpage_lastused win_new_tabpage tabpage_close tabpage_move \
         may_open_tabpage p_stal p_tpm p_tcl tcl_flags postponed_split_tab; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  tabs         $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  tabs         nothing makes, reaches, moves, lists or draws a second tab page"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"
