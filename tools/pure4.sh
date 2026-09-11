#!/bin/sh
# Pure phase 4 -- the binary's name stops choosing what it does.  See PURE-GOAL.md.
#
# Usage: tools/pure4.sh <work-dir>       (run from the repository root)
#
# parse_command_name() reads argv[0] and picks a mode from it -- a leading `r`
# is restricted, `view` is read-only, `ex` is Ex mode.  That is a Unix
# INSTALLATION convention: you symlink rvim, view and ex at one binary and let
# the name decide.  An embedded editor is one file that was never installed and
# has no use for it.
#
# It is also the trap this repository has paid for more than once: a reference
# binary saved as `ref` runs restricted, where every shell-out fails; renaming
# the product to slim-vim needed a side-by-side check first; and every harness
# here stages the binary under test as `vim` for no reason except this function.
#
# NOTHING IS LOST, and tools/noargv0.py checks that rather than asserting it: it
# refuses to run unless -Z, -R, -y, -e and -E all still select the modes the
# name could.  Keeping the options was the requirement; proving they are still
# there is what makes the removal safe.
#
# THE DELTA: none.  The harnesses stage the binary as `vim`, which selected
# plain vim mode before and selects it now, so nothing they record can move.
set -eu

work=${1:?usage: pure3.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")

# --- cut the entry point --------------------------------------------------
python3 tools/noargv0.py "$f"

tools/sweep.sh "$f"

tools/canon.sh "$f"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" helpclose intro version
