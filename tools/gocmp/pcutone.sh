#!/bin/sh
# One comparison, for pcutcmp.sh's xargs.  Usage: pcutone.sh <tool> <src>
# Reads BIN and OUT from the environment.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
tool=$1; src=$2
a=$(mktemp); b=$(mktemp)
trap 'rm -f "$a" "$b"' EXIT
cp "$src" "$a"; cp "$src" "$b"
pa=$(python3 "tools/$tool.py" "$a" 2>&1 || echo "EXIT$?")
pb=$("$BIN" "$tool" "$b" 2>&1 || echo "EXIT$?")
tag=cut
case "$pa" in *EXIT*) tag=refused ;; esac
res="$OUT/$tool.$(basename "$src")"
if printf '%s' "$pa" | grep -q 'Traceback (most recent call last)'; then
    if printf '%s' "$pb" | grep -q EXIT && cmp -s "$src" "$a" && cmp -s "$src" "$b"; then
        echo "same crash" > "$res"
    else
        { echo "differ crash"; echo "py: $pa"; echo "go: $pb"; } > "$res"
    fi
elif [ "$pa" = "$pb" ] && cmp -s "$a" "$b"; then
    echo "same $tag" > "$res"
else
    { echo "differ $tag"; echo "py: $pa"; echo "go: $pb"
      cmp -s "$a" "$b" || echo "  (output files differ)"; } > "$res"
fi
