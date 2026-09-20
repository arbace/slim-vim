#!/bin/sh
# One comparison of an ARGUMENT-TAKING tool, for pargcmp.sh's xargs.
# Usage: pargone.sh "<label>|<src>|<arg> <arg> ..."
# Reads TOOL, BIN and OUT from the environment.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
line=$1
label=${line%%|*}; rest=${line#*|}
src=${rest%%|*}; args=${rest#*|}
a=$(mktemp); b=$(mktemp)
trap 'rm -f "$a" "$b"' EXIT
cp "$src" "$a"; cp "$src" "$b"
# shellcheck disable=SC2086
pa=$(python3 "tools/$TOOL.py" "$a" $args 2>&1 || echo "EXIT$?")
# shellcheck disable=SC2086
pb=$("$BIN" "$TOOL" "$b" $args 2>&1 || echo "EXIT$?")
tag=cut
case "$pa" in *EXIT*) tag=refused ;; esac
res="$OUT/$label.$(basename "$src")"
if [ "$pa" = "$pb" ] && cmp -s "$a" "$b"; then
    echo "same $tag" > "$res"
else
    { echo "differ $tag"; echo "py: $pa"; echo "go: $pb"
      cmp -s "$a" "$b" || echo "  (output files differ)"; } > "$res"
fi
