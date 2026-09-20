#!/bin/sh
# oracle.sh vs `slimtools oracle`, on all three of its paths: a boundary that
# matches, one that differs, and one that was never recorded.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)

o=$(mktemp -d)
cp .build-whim/q41.sha256 "$o/q41.sha256"
cp .build-whim/q41.sha256.files "$o/q41.sha256.files" 2>/dev/null || true
# A boundary that differs: q63's digest recorded where q41's belongs.
cp .build-whim/q63.sha256 "$o/q12.sha256"
cp .build-whim/q63.sha256.files "$o/q12.sha256.files" 2>/dev/null || true

for phase in 41 12 80; do
    a=$(sh tools/oracle.sh "$phase" .build-whim "$o" whim 2>&1 || true)
    b=$(./"$bin" oracle "$phase" .build-whim "$o" whim 2>&1 || true)
    sa=$(sh tools/oracle.sh "$phase" .build-whim "$o" whim >/dev/null 2>&1 && echo 0 || echo 1)
    sb=$(./"$bin" oracle "$phase" .build-whim "$o" whim >/dev/null 2>&1 && echo 0 || echo 1)
    echo "--- q$phase (shell exit $sa, go exit $sb) ---"
    echo "shell: $a" | head -3
    echo "go   : $b" | head -3
done
rm -rf "$o"
