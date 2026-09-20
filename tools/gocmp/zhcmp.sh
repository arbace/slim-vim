#!/bin/sh
# zhostonly.py vs `slimtools zhostonly`, on every zero boundary from r20 on --
# the boundaries whose checks actually run it -- and on the ones before, where
# it must refuse for the same reason.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0
for f in "$@"; do
    a=$(python3 tools/zhostonly.py "$f" 2>&1 || echo "EXIT$?")
    b=$(./"$bin" zhostonly "$f" 2>&1 || echo "EXIT$?")
    if [ "$a" = "$b" ]; then
        same=$((same + 1))
        printf '  %-18s same  %s\n' "$(basename "$f")" "$(echo "$a" | head -1 | cut -c1-70)"
    else
        diff=$((diff + 1))
        printf '  %-18s DIFFER\npy:\n%s\ngo:\n%s\n' "$(basename "$f")" "$a" "$b"
    fi
done
echo "zhostonly: $same same, $diff differ"
[ "$diff" -eq 0 ]
