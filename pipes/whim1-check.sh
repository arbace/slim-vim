#!/bin/sh
# Whim phase 1, the check -- no $VIMRUNTIME.
# See pipes/whim1-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim1-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim1-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim1-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim1-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# --- it must build, and say nothing --------------------------------------
tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, stated in advance and checked ----------------------------
# Exactly ONE command changes what the sweep records, and the reason is worth
# stating because it is not the obvious one.  The sweep runs in an environment
# with no runtime installed -- which is the target environment -- so :help,
# :helptags, :runtime, :exusage and :viusage were ALREADY failing in slim-vim:
# they went looking for files that were not there.  Pointing them at ex_ni
# changes the message and not the outcome.
#
# :helpclose is the exception, and the only honest entry in this list: closing a
# help window that is not open is a no-op that SUCCEEDS, so it is the one row
# whose recorded result moves from ok to E319.
#
# The user-visible delta is larger than this, on a machine that does have a vim
# runtime installed.  The harness cannot see that and does not pretend to; what
# it can prove is that nothing ELSE moved.
tools/whimdelta.sh "$work/whim-vim" "$f" helpclose
