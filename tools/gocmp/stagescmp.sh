#!/bin/sh
# stages.sh vs `slimtools stages`, on all three modes and both pipelines with
# a manifest -- plus the failure path, which is the one that matters.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0

cmp_out() {   # cmp_out <label> <args...>
    a=$(sh tools/stages.sh "$@" 2>&1 || echo "EXIT$?")
    b=$(./"$bin" stages "$@" 2>&1 || echo "EXIT$?")
    if [ "$a" = "$b" ]; then
        same=$((same + 1)); printf '  %-26s same\n' "$1 ${2:-} ${3:-}"
    else
        diff=$((diff + 1)); printf '  %-26s DIFFER\nshell:\n%s\ngo:\n%s\n' "$1 ${2:-} ${3:-}" "$a" "$b"
    fi
}

for p in slim whim zero; do
    cmp_out "$p"
    cmp_out "$p" --check
done
cmp_out whim --of 41
cmp_out zero --of 45
cmp_out zero --of 999

echo "stages: $same same, $diff differ"
[ "$diff" -eq 0 ]
