#!/bin/sh
# Whim phase 2, the check -- the options for features that are not here.
# See pipes/whim2-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim2-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim2-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim2-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim2-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta: nothing NEW, which is the claim ---------------------------
# The declared list is CUMULATIVE, measured against slim-vim's own recorded
# baselines rather than against the previous whim phase.  That is the composable
# form: each phase states the whole difference from slim, so the list can only
# grow and a phase that quietly undid an earlier one would show up.
#
# This phase adds nothing to it.  Every command here was already ex_ni, so the
# Ex sweep records nothing new; what changed is `:set`, which the sweep does not
# exercise.  The evidence that work happened is the score, not the delta, and
# saying so is better than inventing a delta to point at.
tools/whimdelta.sh "$work/whim-vim" "$f" helpclose
