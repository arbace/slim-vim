#!/bin/sh
# orphanopts.py vs `slimtools orphanopts`, over the whole corpus.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0
for f in "$@"; do
    a=$(python3 tools/orphanopts.py "$f" 2>&1 || echo "EXIT$?")
    b=$(./"$bin" orphanopts "$f" 2>&1 || echo "EXIT$?")
    if [ "$a" = "$b" ]; then
        same=$((same + 1))
    else
        diff=$((diff + 1))
        printf '  %s DIFFER\npy:\n%s\ngo:\n%s\n' "$(basename "$f")" "$a" "$b"
    fi
done
echo "orphanopts: $same same, $diff differ"
[ "$diff" -eq 0 ]
