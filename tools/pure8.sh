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

sweep=0
while :; do
    sweep=$((sweep + 1))
    was=$(sha256sum "$f" | cut -d' ' -f1)
    a=$(python3 tools/deadsweep.py "$f" | tail -1)
    c=$(python3 tools/deadprotos.py "$f" | tail -1)
    b=$(python3 tools/typereach.py "$f" --delete | tail -1)
    echo "  sweep $sweep      $a; $c; $b"
    [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$was" ] && break
    [ "$sweep" -ge 15 ] && { echo "  sweep        not converging"; exit 1; }
done

tools/canon.sh "$f"

warn=$(gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o /dev/null "$f" 2>&1 \
       | grep 'warning:' | grep -cv 'implicit-fallthrough' || true)
if [ "$warn" != 0 ]; then
    echo "  warnings     $warn besides the fall-throughs -- the sweep is not finished"
    gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o /dev/null "$f" 2>&1 \
        | grep 'warning:' | grep -v 'implicit-fallthrough' | head -5 | sed 's/^/               /'
    exit 1
fi

# The invariant this phase could silently break, checked rather than assumed.
# nm the OBJECT: a static binary defines 1,400-odd symbols of its own and would
# bury the answer.
gcc -c -O0 -o "$work/nm.o" "$f" 2>/dev/null
ext=$(nm --extern-only --defined-only "$work/nm.o" | awk '{print $NF}' | grep -v '^main$' || true)
rm -f "$work/nm.o"
if [ -n "$ext" ]; then
    echo "  linkage      these became external: $ext"
    echo '               a dropped static declaration is a dropped linkage'
    exit 1
fi
echo "  linkage      nm on the object still prints exactly main"

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" helpclose intro version
