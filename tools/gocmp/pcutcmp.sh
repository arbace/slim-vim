#!/bin/sh
# cutcmp, in parallel.  Usage: pcutcmp.sh <tool>...
#
# The sequential form is I/O bound -- two copies of a ~600 KB file and two
# process spawns per comparison, 482 files a tool -- and spends a few CPU
# seconds over tens of minutes on a 64-CPU machine.  This runs one comparison
# per job, through pcutone.sh, and joins the verdicts afterwards.
#
# The verdicts are written to FILES and counted at the end rather than summed
# in the shell, because a counter incremented inside a pipeline or a subshell
# is lost when it exits.  Each job also writes its verdict to its own path, so
# two jobs finishing at once cannot interleave a line.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
BIN=$PWD/$(sh tools/gobuild.sh)
OUT=$(mktemp -d)
export BIN OUT
trap 'rm -rf "$OUT"' EXIT

for tool in "$@"; do
    for src in ${GOCMP_CORPUS:-.gocorpus}/*/*.c; do
        printf '%s\n%s\n' "$tool" "$src"
    done
done | xargs -P "$(nproc)" -n 2 sh ${GOCMP:-tools/gocmp}/pcutone.sh

count() { grep -l "$1" "$OUT"/* 2>/dev/null | wc -l; }
same=$(count '^same'); diff=$(count '^differ')
cut=$(count '^same cut'); refused=$(count '^same refused'); crash=$(count '^same crash')
[ "$diff" -eq 0 ] || grep -h -A3 '^differ' "$OUT"/* | head -60
echo "pcutcmp [$*]: $same same, $diff differ ($cut cut, $refused refused, $crash python-raised)"
[ "$cut" -gt 0 ] || { echo "VACUOUS: nothing was actually cut"; exit 1; }
[ "$diff" -eq 0 ]
