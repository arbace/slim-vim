#!/bin/sh
# zcompare.py vs `slimtools zcompare`: the --declared parse for every phase,
# and a full comparison of the baselines against themselves (where nothing
# moved, so every declared token must be reported as static).
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0

n=0
while [ "$n" -le 45 ]; do
    a=$(python3 tools/zcompare.py --declared pipes/zero.delta "$n" 2>&1 || echo "EXIT$?")
    b=$(./"$bin" zcompare --declared pipes/zero.delta "$n" 2>&1 || echo "EXIT$?")
    if [ "$a" = "$b" ]; then same=$((same + 1)); else
        diff=$((diff + 1)); printf '  --declared %s DIFFER\npy: %s\ngo: %s\n' "$n" "$a" "$b"
    fi
    n=$((n + 1))
done

base=.reference/zero-baselines
if [ -d "$base/screen" ]; then
    for p in 0 2 11 39 45; do
        a=$(python3 tools/zcompare.py "$base" "$base" pipes/zero.delta "$p" 2>&1 || echo "EXIT$?")
        b=$(./"$bin" zcompare "$base" "$base" pipes/zero.delta "$p" 2>&1 || echo "EXIT$?")
        if [ "$a" = "$b" ]; then
            same=$((same + 1)); printf '  self-compare phase %-3s same\n' "$p"
        else
            diff=$((diff + 1)); printf '  self-compare phase %-3s DIFFER\npy:\n%s\ngo:\n%s\n' "$p" "$a" "$b"
        fi
    done
fi
echo "zcompare: $same same, $diff differ"
[ "$diff" -eq 0 ]
