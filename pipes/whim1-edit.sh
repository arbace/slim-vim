#!/bin/sh
# Whim phase 1 -- no $VIMRUNTIME.  See WHIM-GOAL.md.
#
# Usage: pipes/whim1-edit.sh <work-dir> <state-dir>       (run from the repository root)
#
# The first ground truth: nothing is installed beside the binary, so every path
# that goes looking for a runtime directory is dead weight and, worse, a promise
# the editor cannot keep.  `:help` that opens nothing is more confusing than
# `:help` that says it is not implemented.
#
# The removal is COMPUTED.  `noruntime` cuts four entry points -- six
# command rows, the runtime path strings, the runtimepath builders and the
# branch of vim_getenv() that derives a runtime directory from argv[0] -- and
# then the ordinary dead-code sweep finds everything unreachable behind them.
# Nothing here names a function to delete.
#
# THE DELTA THIS PHASE IS ALLOWED TO CAUSE, and nothing else: the six commands
# report E319 instead of acting, and 'helpfile' and 'runtimepath' report empty.
# That is checked below against slim-vim's own recorded baselines, which is what
# makes this a phase rather than an edit.
set -eu

work=${1:?usage: whim1-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
base=.reference/baselines

# --- cut the entry points -------------------------------------------------
tools/st.sh noruntime "$f"

# --- and let the sweep find the rest --------------------------------------
# Alternating to a joint fixpoint, exactly as the slim pipeline's phase 8 does:
# deleting a function orphans its callees, deleting a prototype orphans a type,
# and a type sweep run once would miss both.

# tools/phaserun.sh sweeps next, then runs pipes/whim1-check.sh.
