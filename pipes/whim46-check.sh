#!/bin/sh
# Whim phase 46, the check -- no :wall, :qall, :quitall, :wqall or :xall.
# See pipes/whim46-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim46-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim46-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim46-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim46-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in do_wqall ex_quit_all; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  allcmds      $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  allcmds      nothing is left of the -all commands"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# :q! must still quit -- every harness depends on it now -- and :qa! must not.
out=$(cd "$work" && ./whim-vim -e -s '+q!' </dev/null 2>&1) && rc=0 || rc=$?
[ "$rc" = 0 ] || { echo "  quit         +q! exits $rc: $out"; exit 1; }
out=$(cd "$work" && ./whim-vim -e -s '+qa!' </dev/null 2>&1) && rc=0 || rc=$?
[ "$rc" = 1 ] || { echo "  quit         +qa! exits $rc, expected 1: $out"; exit 1; }
echo "  quit         :q! quits, :qa! is not a command"
