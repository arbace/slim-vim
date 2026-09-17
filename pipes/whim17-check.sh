#!/bin/sh
# Whim phase 17, the check -- the last two per-buffer encoding options.
# See pipes/whim17-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim17-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim17-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim17-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim17-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The post-condition, and the check that was missing when this phase first ran.
# dropoptions.py --strict asks "does anything still read this global?", but it
# has to ask BEFORE the sweep, when the option's own callback still does.  After
# the sweep the question is answerable and the answer must be nothing at all --
# an unread global is itself swept, so the right count is zero mentions, not one.
# The names as well as the globals.  set_string_option_direct((char_u *)"fenc")
# resolves an option through findoption(), which answers -1 for a row that is
# not there, and the caller does not check -- silent Ex mode then exits 1
# without printing, and every recorded exit status in the harness moves at once.
# That is what this phase did on its first run, and what Phase 15 did with
# "fencs".  dropoptions.py's name guard is --strict, and --local skips it.
for g in p_fenc p_bomb b_start_fenc b_start_bomb '"fenc"' '"bomb"'; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  globals      $g still has $n mentions after the sweep"
        echo "               a dropped row leaves its global uninitialised, and a"
        echo "               reader of it is a segfault before the first keystroke"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  globals      neither option is named or read anywhere any more"


tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"
