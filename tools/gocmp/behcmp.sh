#!/bin/sh
# behaviour.py vs `slimtools behaviour`, on real boundary binaries, and
# against the recorded slim baselines.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0
for t in .build-whim/q82.tar .build-whim/q41.tar .build-zero/r45.tar; do
    [ -f "$t" ] || continue
    w=$(mktemp -d); tar xf "$t" -C "$w"
    v=$(find "$w" -maxdepth 1 -name '*-vim' -type f | head -1)
    [ -n "$v" ] || { rm -rf "$w"; continue; }
    python3 tools/behaviour.py "$v" "$w/py" >/dev/null
    ./"$bin" behaviour "$v" "$w/go" >/dev/null
    if diff -rq "$w/py" "$w/go" >/dev/null 2>&1; then
        same=$((same + 1)); printf '  %-12s same (%s cases)\n' "$(basename "$t")" "$(ls "$w/py" | wc -l)"
    else
        diff=$((diff + 1)); printf '  %-12s DIFFER\n' "$(basename "$t")"
        diff -rq "$w/py" "$w/go" | head -6 || true
    fi
    rm -rf "$w"
done
echo "behaviour: $same same, $diff differ"
[ "$diff" -eq 0 ]
