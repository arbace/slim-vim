#!/bin/sh
# memo's cache key, computed as memo.sh computes it, against what the Go memo
# would look up.  The key is unit + input boundary + implementation, which is
# the only thing a cached result is an answer to.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0

shell_key() {   # shell_key <pipeline> <tag> <build> <unit>
    p=$1; tag=$2; build=$3; unit=$4
    first=${unit%-*}
    if [ "$first" = 0 ]; then
        d=$(cat "$build/input.sha256")
    else
        d=$(cat "$build/$tag$((first - 1)).sha256")
    fi
    i=$(sh tools/implhash.sh "$unit" "$p")
    printf '%s\n%s\n%s\n' "$unit" "$d" "$i" | sha256sum | cut -c1-32
}

one() {   # one <pipeline> <tag> <build>
    p=$1; tag=$2; build=$3
    for u in $(awk '$1 == "stage" { print $2 }' "pipes/$p.stages"); do
        first=${u%-*}
        if [ "$first" != 0 ] && [ ! -f "$build/$tag$((first - 1)).sha256" ]; then
            continue
        fi
        a=$(shell_key "$p" "$tag" "$build" "$u")
        b=$(./"$bin" memokey "$u" "$build" "$p" 2>/dev/null || echo NOCMD)
        if [ "$a" = "$b" ]; then
            same=$((same + 1))
        else
            diff=$((diff + 1))
            printf '  %s %-8s shell=%s go=%s\n' "$p" "$u" "$a" "$b"
        fi
    done
}

one whim q .build-whim
one zero r .build-zero
echo "memokey: $same same, $diff differ"
[ "$diff" -eq 0 ]
