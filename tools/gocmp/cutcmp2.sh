#!/bin/sh
# nostat and nofnamemod: Go against Python, on every corpus file.
#
# A cutter that refuses must refuse with the same words, so the refusals are
# compared as carefully as the successes -- and both are counted, because a
# comparison where every input refused would agree vacuously.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0; cut=0; refused=0

for tool in notags nofind; do
    for src in ${GOCMP_CORPUS:-.gocorpus}/*/*.c; do
        a=$(mktemp); b=$(mktemp)
        cp "$src" "$a"; cp "$src" "$b"
        pa=$(python3 "tools/$tool.py" "$a" 2>&1 || echo "EXIT$?")
        pb=$(./"$bin" "$tool" "$b" 2>&1 || echo "EXIT$?")
        case "$pa" in *EXIT*) refused=$((refused + 1)) ;; *) cut=$((cut + 1)) ;; esac
        if [ "$pa" = "$pb" ] && cmp -s "$a" "$b"; then
            same=$((same + 1))
        else
            diff=$((diff + 1))
            printf '%-12s %-22s DIFFER\npy: %s\ngo: %s\n' \
                "$tool" "$(basename "$src")" "$pa" "$pb"
            cmp -s "$a" "$b" || echo "  (output files differ)"
        fi
        rm -f "$a" "$b"
    done
done

echo "cutcmp2: $same same, $diff differ ($cut cut, $refused refused)"
[ "$cut" -gt 0 ] || { echo "VACUOUS: nothing was actually cut"; exit 1; }
[ "$diff" -eq 0 ]
