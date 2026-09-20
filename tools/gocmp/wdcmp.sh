#!/bin/sh
# whimdelta.sh vs `slimtools whimdelta`, on real boundary binaries.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0
for q in 82 41 12; do
    t=.build-whim/q$q.tar
    [ -f "$t" ] || continue
    w=$(mktemp -d)
    tar xf "$t" -C "$w"
    [ -x "$w/whim-vim" ] || { echo "  q$q: no binary in the tar"; rm -rf "$w"; continue; }
    a=$(sh tools/whimdelta.sh "$w/whim-vim" "$w/whim-vim.c" --phase "$q" 2>&1 || echo "EXIT$?")
    b=$(./"$bin" whimdelta "$w/whim-vim" "$w/whim-vim.c" --phase "$q" 2>&1 || echo "EXIT$?")
    if [ "$a" = "$b" ]; then
        same=$((same + 1)); printf '  q%-3s same\n%s\n' "$q" "$a"
    else
        diff=$((diff + 1)); printf '  q%-3s DIFFER\nshell:\n%s\ngo:\n%s\n' "$q" "$a" "$b"
    fi
    rm -rf "$w"
done
echo "whimdelta: $same same, $diff differ"
[ "$diff" -eq 0 ]
