#!/bin/sh
# Pure phase 1 -- no $VIMRUNTIME.  See PURE-GOAL.md.
#
# Usage: tools/pure1.sh <work-dir>       (run from the repository root)
#
# The first ground truth: nothing is installed beside the binary, so every path
# that goes looking for a runtime directory is dead weight and, worse, a promise
# the editor cannot keep.  `:help` that opens nothing is more confusing than
# `:help` that says it is not implemented.
#
# The removal is COMPUTED.  tools/noruntime.py cuts four entry points -- six
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

work=${1:?usage: pure1.sh <work-dir>}
f="$work/pure-vim.c"
base=.reference/baselines

before_lines=$(grep -c '' "$f")

# --- cut the entry points -------------------------------------------------
python3 tools/noruntime.py "$f"

# --- and let the sweep find the rest --------------------------------------
# Alternating to a joint fixpoint, exactly as the slim pipeline's phase 8 does:
# deleting a function orphans its callees, deleting a prototype orphans a type,
# and a type sweep run once would miss both.
tools/sweep.sh "$f"

tools/canon.sh "$f"

# --- it must build, and say nothing --------------------------------------
tools/phasecheck.sh "$work" "$f" .cache/symbols/before

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

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
tools/puredelta.sh "$work/pure-vim" "$f" helpclose
