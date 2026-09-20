#!/bin/sh
# Control: the Go harness must DISCRIMINATE.  Two different binaries have to
# produce different recordings, and both implementations have to disagree in
# the same places -- otherwise "3 of 3 same" only says both harnesses are
# equally blind.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
w=$(mktemp -d)
tar xf .build-whim/q41.tar -C "$w/" --one-top-level=a
tar xf .build-whim/q82.tar -C "$w/" --one-top-level=b
va=$(find "$w/a" -maxdepth 1 -name '*-vim' -type f | head -1)
vb=$(find "$w/b" -maxdepth 1 -name '*-vim' -type f | head -1)

python3 tools/behaviour.py "$va" "$w/pa" >/dev/null
python3 tools/behaviour.py "$vb" "$w/pb" >/dev/null
./"$bin" behaviour "$va" "$w/ga" >/dev/null
./"$bin" behaviour "$vb" "$w/gb" >/dev/null

py=$(diff -rq "$w/pa" "$w/pb" 2>/dev/null | grep -c '^Files' || true)
go=$(diff -rq "$w/ga" "$w/gb" 2>/dev/null | grep -c '^Files' || true)
echo "q41 vs q82: python sees $py cases differ, go sees $go"
pn=$(diff -rq "$w/pa" "$w/pb" 2>/dev/null | sed 's/.*pa\///; s/ and .*//' | sort | tr '\n' ' ')
gn=$(diff -rq "$w/ga" "$w/gb" 2>/dev/null | sed 's/.*ga\///; s/ and .*//' | sort | tr '\n' ' ')
echo "python: $pn"
echo "go    : $gn"
[ "$pn" = "$gn" ] && echo "SAME SET" || echo "DIFFERENT SETS"
rm -rf "$w"
