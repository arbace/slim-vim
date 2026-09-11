#!/bin/sh
# Pure phase 9 -- the table moves below what it names.  See PURE-GOAL.md.
#
# Usage: tools/pure9.sh <work-dir>       (run from the repository root)
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
