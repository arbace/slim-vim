#!/bin/sh
# ztermcheck.py and zpty.py vs their Go subcommands, on real zero binaries.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0
for t in .build-zero/r45.tar .build-zero/r20.tar; do
    [ -f "$t" ] || continue
    w=$(mktemp -d); tar xf "$t" -C "$w"
    v="$w/zero-vim"
    [ -x "$v" ] || { rm -rf "$w"; continue; }

    python3 tools/ztermcheck.py "$v" "$w/py-tc.txt" >/dev/null
    ./"$bin" ztermcheck "$v" "$w/go-tc.txt" >/dev/null
    if cmp -s "$w/py-tc.txt" "$w/go-tc.txt"; then
        same=$((same + 1)); printf '  %-10s ztermcheck same (%s rows)\n' "$(basename "$t")" "$(grep -c '' "$w/py-tc.txt")"
    else
        diff=$((diff + 1)); printf '  %-10s ztermcheck DIFFER\n' "$(basename "$t")"
        diff "$w/py-tc.txt" "$w/go-tc.txt" | head -8 || true
    fi

    python3 tools/zpty.py "$v" "$w/py-pty.txt" >/dev/null 2>&1 || true
    ./"$bin" zpty "$v" "$w/go-pty.txt" >/dev/null 2>&1 || true
    if cmp -s "$w/py-pty.txt" "$w/go-pty.txt"; then
        same=$((same + 1)); printf '  %-10s zpty       same (%s scenarios)\n' "$(basename "$t")" "$(grep -c '^=== ' "$w/py-pty.txt")"
    else
        diff=$((diff + 1)); printf '  %-10s zpty       DIFFER\n' "$(basename "$t")"
        diff "$w/py-pty.txt" "$w/go-pty.txt" | head -12 || true
    fi
    rm -rf "$w"
done
echo "ztermcheck/zpty: $same same, $diff differ"
[ "$diff" -eq 0 ]
