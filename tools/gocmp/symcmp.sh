#!/bin/sh
# symbols.sh vs `slimtools symbols`, with the content cache cleared between
# runs so the second is not merely reading the first's answer.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0
for f in "$@"; do
    a=$(mktemp -d); b=$(mktemp -d)
    rm -rf .cache/symbols
    sh tools/symbols.sh "$f" "$a"
    rm -rf .cache/symbols
    ./"$bin" symbols "$f" "$b"
    if cmp -s "$a/undefined" "$b/undefined" && cmp -s "$a/external" "$b/external"; then
        same=$((same + 1))
        printf '  %-28s same  (%s undefined, %s external)\n' "$(basename "$f")" \
            "$(wc -l < "$a/undefined")" "$(wc -l < "$a/external")"
    else
        diff=$((diff + 1))
        printf '  %-28s DIFFER\n' "$(basename "$f")"
        diff "$a/undefined" "$b/undefined" | head -5 || true
        diff "$a/external" "$b/external" | head -5 || true
    fi
    rm -rf "$a" "$b"
done
echo "symbols: $same same, $diff differ"
[ "$diff" -eq 0 ]
