#!/bin/sh
# Whim phase 29, the check -- :command, user-defined commands.
# See pipes/whim29-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim29-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim29-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim29-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim29-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in do_ucmd uc_check_code uc_add_command b_ucmds ex_delcommand; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  ucmd         $g still has $n mentions after the sweep"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  ucmd         no user command table, and no dispatch into one"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"
