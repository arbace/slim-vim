#!/bin/sh
# Whim phase 6, the check -- the editor stops writing shell scripts, and stops drawing a completion menu.
# See pipes/whim6-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim6-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim6-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim6-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim6-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# SLIM-GOAL.md phase 7's invariant, checked again because this phase moved a
# declaration: nowild.py reuses the slot the shell expander's prototype held,
# and a declaration that loses its `static` hands external linkage to one
# that never said so itself.  nm the OBJECT -- a static binary defines 1,400
# symbols of its own and would bury the answer.
tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"
