#!/bin/sh
# Whim phase 70, the check -- :e reloads in place, and there is no swap file.
# See pipes/whim70-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim70-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim70-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.

# THE BODY IS GO: tools/go/internal/check/whime.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/phasebuild.sh
#   tools/phasecheck.sh
#   tools/st.sh
set -eu

work=${1:?usage: whim70-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim70-check.sh <work-dir> <state-dir>}
exec tools/st.sh check whim70 "$work" "$state"
