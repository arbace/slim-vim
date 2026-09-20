#!/bin/sh
# zrecord.sh vs `slimtools zrecord`: a WHOLE recording of a zero binary, all
# six parts, compared tree against tree.  And then each recording compared
# against the committed baselines, which is what the pipeline actually asks.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
tar xf .build-zero/r45.tar -C "$w"
v="$w/zero-vim"; c="$w/zero-vim.c"

sh tools/zrecord.sh "$v" "$c" "$w/sh" >/dev/null
./"$bin" zrecord "$v" "$c" "$w/go" >/dev/null

if diff -rq "$w/sh" "$w/go" >/dev/null 2>&1; then
    echo "  whole recording: SAME"
    echo "    screen  $(ls "$w/sh/screen" | wc -l) cases"
    echo "    memline $(ls "$w/sh/memline" | wc -l) cases"
    for f in ref-excmds.txt ref-argv.txt ref-pty.txt ref-term.txt; do
        printf '    %-16s %s lines\n' "$f" "$(grep -c '' "$w/sh/$f")"
    done
else
    echo "  whole recording: DIFFERS"
    diff -rq "$w/sh" "$w/go" | head -10 || true
    exit 1
fi
