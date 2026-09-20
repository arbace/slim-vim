#!/bin/sh
# zargv.py and zexcmds.py vs their Go subcommands, on real zero binaries.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0
for t in .build-zero/r45.tar .build-zero/r20.tar; do
    [ -f "$t" ] || continue
    w=$(mktemp -d); tar xf "$t" -C "$w"
    v="$w/zero-vim"; c="$w/zero-vim.c"
    [ -x "$v" ] && [ -f "$c" ] || { rm -rf "$w"; continue; }

    python3 tools/zargv.py "$v" "$w/py-argv.txt" >/dev/null
    ./"$bin" zargv "$v" "$w/go-argv.txt" >/dev/null
    if cmp -s "$w/py-argv.txt" "$w/go-argv.txt"; then
        same=$((same + 1)); printf '  %-10s zargv    same (%s rows)\n' "$(basename "$t")" "$(grep -c '^=== ' "$w/py-argv.txt")"
    else
        diff=$((diff + 1)); printf '  %-10s zargv    DIFFER\n' "$(basename "$t")"
        diff "$w/py-argv.txt" "$w/go-argv.txt" | head -10 || true
    fi

    python3 tools/zexcmds.py "$v" "$c" "$w/py-ex.txt" >/dev/null
    ./"$bin" zexcmds "$v" "$c" "$w/go-ex.txt" >/dev/null
    if cmp -s "$w/py-ex.txt" "$w/go-ex.txt"; then
        same=$((same + 1)); printf '  %-10s zexcmds  same (%s rows)\n' "$(basename "$t")" "$(grep -c '^=== ' "$w/py-ex.txt")"
    else
        diff=$((diff + 1)); printf '  %-10s zexcmds  DIFFER\n' "$(basename "$t")"
        diff "$w/py-ex.txt" "$w/go-ex.txt" | head -10 || true
    fi
    rm -rf "$w"
done
echo "zargv/zexcmds: $same same, $diff differ"
[ "$diff" -eq 0 ]
