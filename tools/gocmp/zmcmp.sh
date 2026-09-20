#!/bin/sh
# zmemline.py vs `slimtools zmemline`: sixteen cases of up to 25,000 lines,
# built in the editor.  Slow by nature -- the lines are TYPED.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0
for t in .build-zero/r45.tar; do
    [ -f "$t" ] || continue
    w=$(mktemp -d); tar xf "$t" -C "$w"
    v="$w/zero-vim"
    [ -x "$v" ] || { rm -rf "$w"; continue; }
    python3 tools/zmemline.py "$v" "$w/py" >/dev/null
    ./"$bin" zmemline "$v" "$w/go" >/dev/null
    if diff -rq "$w/py" "$w/go" >/dev/null 2>&1; then
        same=$((same + 1)); printf '  %-10s same (%s cases)\n' "$(basename "$t")" "$(ls "$w/py" | wc -l)"
    else
        diff=$((diff + 1)); printf '  %-10s DIFFER\n' "$(basename "$t")"
        diff -rq "$w/py" "$w/go" | head -6 || true
        f=$(diff -rq "$w/py" "$w/go" | head -1 | sed 's/.*py\///; s/ and .*//')
        [ -n "$f" ] && diff "$w/py/$f" "$w/go/$f" | head -14 || true
    fi
    rm -rf "$w"
done
echo "zmemline: $same same, $diff differ"
[ "$diff" -eq 0 ]
