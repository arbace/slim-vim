#!/bin/sh
# Pure phase 7 -- the table moves below what it names.  See PURE-GOAL.md.
#
# Usage: tools/pure7.sh <work-dir>       (run from the repository root)
#
# cmdnames[] names six hundred Ex command handlers and sits near the top of the
# file, so each of them needs a forward declaration -- not because anything
# calls them early, but because a table mentions them early.  Moving the table
# below its handlers removes those, and costs one declaration of the table.
#
# Two of the three candidate tables CANNOT move, and the reason is a language
# rule rather than a gap in the tooling: options[] and nv_cmds[] are measured
# with sizeof() by functions defined above them, and a tentative declaration of
# an array has no size.  Trying it fails at exactly that sizeof.  They keep
# their 229 declarations; cmdnames gives up 98.
#
# THE DELTA: none.  Where a table sits is not behaviour.
set -eu

work=${1:?usage: pure3.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")

# --- move it, then take the declarations it was forcing -------------------
python3 tools/movetables.py "$f" cmdnames
python3 tools/dropprotos.py "$f" --delete

tools/sweep.sh "$f"

tools/canon.sh "$f"


# The invariant this phase could silently break, checked rather than assumed.
# nm the OBJECT: a static binary defines 1,400-odd symbols of its own and would
# bury the answer.
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
