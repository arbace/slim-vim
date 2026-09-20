#!/bin/sh
# One pty session, to prove the master now takes a read deadline and the
# session ends instead of hanging.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
tar xf .build-whim/q82.tar -C "$w"
v=$(find "$w" -maxdepth 1 -name '*-vim' -type f | head -1)
start=$(date +%s)
timeout 120 ./"$bin" termcheck "$v" "$w/go.txt" > "$w/go.out" 2>&1 || echo "(exit $?)"
echo "go termcheck took $(( $(date +%s) - start ))s"
head -6 "$w/go.txt" 2>/dev/null || echo "(no output file)"
