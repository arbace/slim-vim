#!/bin/sh
# Run one cutter both ways on one file and show both outputs.
# Usage: one.sh <tool> <src>
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
tool=$1; src=$2
a=$(mktemp); b=$(mktemp)
cp "$src" "$a"; cp "$src" "$b"
echo "=== python:"
python3 "tools/$tool.py" "$a" 2>&1 | head -20 || echo "EXIT$?"
echo "=== go:"
./"$bin" "$tool" "$b" 2>&1 | head -20 || echo "EXIT$?"
echo "=== files:"
cmp "$a" "$b" || true
rm -f "$a" "$b"
