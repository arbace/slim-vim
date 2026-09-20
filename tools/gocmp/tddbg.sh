#!/bin/sh
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
w=$(mktemp -d)
tar xf .build-zero/r45.tar -C "$w"
echo "=== find | sort | sha256sum, first 6 lines ==="
( cd "$w" && find . -type f -print0 | sort -z | xargs -0 sha256sum ) | head -6
echo "=== after the grep -Ev ==="
( cd "$w" && find . -type f -print0 | sort -z | xargs -0 sha256sum ) \
    | grep -Ev '/objects/|\.(o|d)$|/(whim-|zero-)?vim$' | head -6
echo "=== line count before/after grep ==="
( cd "$w" && find . -type f -print0 | sort -z | xargs -0 sha256sum ) | wc -l
( cd "$w" && find . -type f -print0 | sort -z | xargs -0 sha256sum ) \
    | grep -Ev '/objects/|\.(o|d)$|/(whim-|zero-)?vim$' | wc -l
rm -rf "$w"
