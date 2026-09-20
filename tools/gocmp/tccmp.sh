#!/bin/sh
# termcheck.py vs `slimtools termcheck` -- a real pty, nineteen terminals.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0
for t in .build-whim/q82.tar .build-whim/q41.tar; do
    [ -f "$t" ] || continue
    w=$(mktemp -d); tar xf "$t" -C "$w"
    v=$(find "$w" -maxdepth 1 -name '*-vim' -type f | head -1)
    [ -n "$v" ] || { rm -rf "$w"; continue; }
    python3 tools/termcheck.py "$v" "$w/py.txt" >/dev/null
    ./"$bin" termcheck "$v" "$w/go.txt" >/dev/null
    if cmp -s "$w/py.txt" "$w/go.txt"; then
        same=$((same + 1)); printf '  %-12s same (%s rows)\n' "$(basename "$t")" "$(grep -c '' "$w/py.txt")"
    else
        diff=$((diff + 1)); printf '  %-12s DIFFER\n' "$(basename "$t")"
        diff "$w/py.txt" "$w/go.txt" | head -10 || true
    fi
    rm -rf "$w"
done
echo "termcheck: $same same, $diff differ"
[ "$diff" -eq 0 ]
