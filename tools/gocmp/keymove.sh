#!/bin/sh
# Which implementation keys does the cutover move?
#
# sweep.sh and canon.sh are named by phase programs, so tools/implhash.sh
# hashes them into those phases' keys.  A moved key does not change a boundary
# -- it invalidates the tier-3 cache entry, so the phase RE-RUNS and must
# reproduce what it recorded.  That is CPU, not correctness, and this counts
# how much of it.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
out=$1                       # where to write the key table

: > "$out"
for u in $(awk '$1 == "stage" { print $2 }' pipes/whim.stages); do
    printf 'whim %-8s %s\n' "$u" "$(sh tools/implhash.sh "$u" whim)" >> "$out"
done
for p in $(awk '$1 == "stage" { print $2 }' pipes/whim.stages); do
    case $p in *-*) continue ;; esac
done
for n in $(seq 0 82); do
    [ -f "pipes/whim$n-edit.sh" ] || continue
    printf 'whim-edit %-4s %s\n' "$n" "$(sh tools/implhash.sh --edit "$n" whim)" >> "$out"
done
for n in $(seq 0 11); do
    printf 'slim %-8s %s\n' "$n" "$(sh tools/implhash.sh "$n" slim)" >> "$out"
done
for u in $(awk '$1 == "stage" { print $2 }' pipes/zero.stages); do
    printf 'zero %-8s %s\n' "$u" "$(sh tools/implhash.sh "$u" zero)" >> "$out"
done
wc -l < "$out"
