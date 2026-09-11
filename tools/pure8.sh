#!/bin/sh
# Pure phase 8 -- every definition says its own linkage.  See PURE-GOAL.md.
#
# Usage: tools/pure8.sh <work-dir>       (run from the repository root)
#
# 1,473 definitions do not say `static` and are static anyway, because a
# declaration earlier in the file said it for them.  That works, and it is a
# trap with a long fuse: remove the declaration -- for being redundant, for
# tidiness, by accident -- and the function quietly acquires external linkage.
# Nothing fails.  The build is clean, the editor runs, and nm grows a symbol
# that this tree's central claim says cannot exist.
#
# Phase 7 met that trap and worked around it, handing `static` to each
# definition whose declaration it removed.  This finishes the job from the other
# end: after it, no declaration anywhere is load-bearing for anything but ORDER,
# and a prototype can be dropped for being unnecessary without anyone having to
# think about linkage at all.
#
# main is the exception and the only one.  The nm check below is what proves it.
#
# THE DELTA: none.  Linkage is not behaviour -- and at -O0 it is not even code,
# which is why nm is the only witness.
set -eu

work=${1:?usage: pure3.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")

# --- say it explicitly, everywhere ---------------------------------------
python3 tools/allstatic.py "$f" --delete

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
