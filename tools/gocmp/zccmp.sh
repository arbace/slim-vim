#!/bin/sh
# zcases.py vs `slimtools zcases`: 102 screen recordings, byte for byte.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0
for t in .build-zero/r45.tar .build-zero/r20.tar; do
    [ -f "$t" ] || continue
    w=$(mktemp -d); tar xf "$t" -C "$w"
    v="$w/zero-vim"
    [ -x "$v" ] || { rm -rf "$w"; continue; }
    python3 tools/zcases.py "$v" "$w/py" >/dev/null
    ./"$bin" zcases "$v" "$w/go" >/dev/null
    if diff -rq "$w/py" "$w/go" >/dev/null 2>&1; then
        same=$((same + 1)); printf '  %-10s same (%s cases)\n' "$(basename "$t")" "$(ls "$w/py" | wc -l)"
    else
        diff=$((diff + 1)); printf '  %-10s DIFFER\n' "$(basename "$t")"
        diff -rq "$w/py" "$w/go" | head -6 || true
        f=$(diff -rq "$w/py" "$w/go" | head -1 | sed 's/.*py\///; s/ and .*//')
        [ -n "$f" ] && diff "$w/py/$f" "$w/go/$f" | head -12 || true
    fi
    rm -rf "$w"
done
echo "zcases: $same same, $diff differ"
[ "$diff" -eq 0 ]
