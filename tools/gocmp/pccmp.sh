#!/bin/sh
# phasecheck.sh vs `slimtools phasecheck` on real boundary sources.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0
for f in "$@"; do
    for side in sh go; do
        w=$(mktemp -d); b=$(mktemp -d)
        cp "$f" "$w/src.c"
        # A `before` set, so the symbols line takes its two-number form.
        rm -rf .cache/symbols
        sh tools/symbols.sh "$w/src.c" "$b" 2>/dev/null
        rm -rf .cache/compile .cache/symbols
        if [ "$side" = sh ]; then
            out_sh=$(sh tools/phasecheck.sh "$w" "$w/src.c" "$b" 2>&1 || echo "EXIT1")
        else
            out_go=$(./"$bin" phasecheck "$w" "$w/src.c" "$b" 2>&1 || echo "EXIT1")
        fi
        rm -rf "$w" "$b"
    done
    if [ "$out_sh" = "$out_go" ]; then
        same=$((same + 1))
        printf '  %-24s same\n' "$(basename "$f")"
    else
        diff=$((diff + 1))
        printf '  %-24s DIFFER\n' "$(basename "$f")"
        printf 'shell:\n%s\ngo:\n%s\n' "$out_sh" "$out_go"
    fi
done
echo "phasecheck: $same same, $diff differ"
[ "$diff" -eq 0 ]
