#!/bin/sh
# The scoreboard: how much of each phase is still a patch rather than a rule.
#
# Usage: tools/residue.sh
#
# Every phase has a tier-2 implementation somewhere on a line between two
# extremes.  At one end it is a recorded diff -- correct, useless as an
# explanation, and guaranteed to break the next time upstream touches those
# lines.  At the other it is a program that computes what to do from the tree
# in front of it, and upstream can move underneath it without it noticing.
#
# The residue is what is left of the first kind after the second kind has done
# its work, and it is the number to drive down.  Zero means the phase is
# understood; a thousand lines means it is remembered.
set -eu

printf '  %-6s %-10s %10s  %s\n' phase tier residue notes
printf '  %-6s %-10s %10s  %s\n' ----- ---------- ---------- -----
total=0
for p in 0 1 2 3 4 5 6 7 8 9; do
    prog="tools/phase$p.sh"
    res="tools/patches/p$p-residue.patch"
    fixed="tools/patches/phase$p.patch"

    if [ ! -f "$prog" ]; then
        printf '  %-6s %-10s %10s  %s\n' "$p" "agent" "-" \
            "no program yet; one tier-1 run synthesises one"
        continue
    fi

    n=0
    note="computed"
    if [ -f "$res" ]; then
        n=$(grep -c '^[+-][^+-]' "$res" || true)
        note="synthesised residue"
    elif [ -f "$fixed" ]; then
        n=$(grep -c '^[+-][^+-]' "$fixed" || true)
        note="a deliberate patch: the edits are fixed and the tree cannot state them"
    fi
    total=$((total + n))
    printf '  %-6s %-10s %10s  %s\n' "$p" "program" "$n" "$note"
done
printf '  %-6s %-10s %10s\n' "" "total" "$total"
