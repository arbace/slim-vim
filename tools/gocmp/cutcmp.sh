#!/bin/sh
# A cutter in Go against the Python it replaces, on every corpus file.
#
# Usage: cutcmp.sh <tool>...
#
# Three outcomes, counted separately, because collapsing them hides things in
# both directions:
#
#   cut       both cut, the output bytes and the report identical
#   refused   both refused, with the same words
#   crash     the Python raised (a traceback) where the Go refuses with one
#             line.  cutil.drop_if raises ValueError, which no caller catches,
#             so the two CANNOT agree textually here and pretending otherwise
#             would be the comparison lying.  Both still exit non-zero and
#             neither writes the file, which is the property that matters --
#             this counts them so the number is visible rather than absorbed.
#
# It refuses to pass vacuously: if nothing was cut, agreement says nothing
# about the code that does the cutting.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0; cut=0; refused=0; crash=0

for tool in "$@"; do
    for src in ${GOCMP_CORPUS:-.gocorpus}/*/*.c; do
        a=$(mktemp); b=$(mktemp)
        cp "$src" "$a"; cp "$src" "$b"
        pa=$(python3 "tools/$tool.py" "$a" 2>&1 || echo "EXIT$?")
        pb=$(./"$bin" "$tool" "$b" 2>&1 || echo "EXIT$?")
        if printf '%s' "$pa" | grep -q 'Traceback (most recent call last)'; then
            # both must refuse, and neither may have written the file
            if printf '%s' "$pb" | grep -q EXIT && cmp -s "$src" "$a" && cmp -s "$src" "$b"; then
                crash=$((crash + 1)); same=$((same + 1))
            else
                diff=$((diff + 1))
                printf '%-12s %-22s CRASH MISMATCH\npy: %s\ngo: %s\n' \
                    "$tool" "$(basename "$src")" "$pa" "$pb"
            fi
            rm -f "$a" "$b"; continue
        fi
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

echo "cutcmp [$*]: $same same, $diff differ ($cut cut, $refused refused, $crash python-raised)"
[ "$cut" -gt 0 ] || { echo "VACUOUS: nothing was actually cut"; exit 1; }
[ "$diff" -eq 0 ]
