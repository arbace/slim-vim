#!/bin/sh
# Pure phase 7 -- the forward declarations nothing needs.  See PURE-GOAL.md.
#
# Usage: tools/pure7.sh <work-dir>       (run from the repository root)
#
# A forward declaration earns its place only when something uses the function
# before it is defined.  This file carries 2,580 of them; 533 are for functions
# nothing mentions until after their own definition, and say nothing the
# compiler does not already know by the time it matters.
#
# THE HAZARD, and the reason this is a phase rather than a sed: a `static`
# declaration is not only a declaration.  A definition that follows one inherits
# internal linkage from it, which is why 1,817 of the 3,289 definitions here do
# not say `static` themselves and are static anyway.  Delete such a prototype
# and the function silently becomes EXTERNAL -- nm grows a symbol, and this
# tree's whole claim is that main is the only one.  So every dropped prototype
# hands `static` to its definition on the way out, and nm is checked below.
#
# THE DELTA: none.  Declarations are not behaviour.
set -eu

work=${1:?usage: pure3.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")

# --- drop them, repairing linkage as we go --------------------------------
python3 tools/dropprotos.py "$f" --delete

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
