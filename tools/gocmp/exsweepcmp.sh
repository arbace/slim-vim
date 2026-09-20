#!/bin/sh
# exsweep.py vs `slimtools exsweep`, and the command-table parse beneath it,
# on real boundary binaries.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0

for t in .build-whim/q82.tar .build-whim/q41.tar .build-zero/r45.tar; do
    [ -f "$t" ] || continue
    w=$(mktemp -d); tar xf "$t" -C "$w"
    v=$(find "$w" -maxdepth 1 -name '*-vim' -type f | head -1)
    c=$(find "$w" -maxdepth 1 -name '*.c' | head -1)
    [ -n "$v" ] && [ -n "$c" ] || { rm -rf "$w"; continue; }

    # the table parse alone
    a=$(python3 -c "
import sys; sys.path.insert(0, 'tools')
import create_cmdidxs as c
print('\n'.join(c.names(sys.argv[1])))" "$c")
    b=$(./"$bin" cmdnames "$c")
    if [ "$a" = "$b" ]; then
        same=$((same + 1)); printf '  %-12s cmdnames same (%s rows)\n' "$(basename "$t")" "$(echo "$a" | grep -c '')"
    else
        diff=$((diff + 1)); printf '  %-12s cmdnames DIFFER\n' "$(basename "$t")"
    fi

    # the whole sweep
    python3 tools/exsweep.py "$v" "$c" "$w/py.txt" >/dev/null
    ./"$bin" exsweep "$v" "$c" "$w/go.txt" >/dev/null
    if cmp -s "$w/py.txt" "$w/go.txt"; then
        same=$((same + 1)); printf '  %-12s exsweep  same (%s rows)\n' "$(basename "$t")" "$(grep -c '' "$w/py.txt")"
    else
        diff=$((diff + 1)); printf '  %-12s exsweep  DIFFER\n' "$(basename "$t")"
        diff "$w/py.txt" "$w/go.txt" | head -8 || true
    fi
    rm -rf "$w"
done
echo "exsweep: $same same, $diff differ"
[ "$diff" -eq 0 ]
