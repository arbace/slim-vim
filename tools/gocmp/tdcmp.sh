#!/bin/sh
# tree_digest, as phaserun.sh computes it, against `slimtools treedigest`.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)

shell_td() {   # the exact pipeline from tools/phaserun.sh
    ( cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum ) \
        | grep -Ev '/objects/|\.(o|d)$|/(whim-|zero-)?vim$' | sha256sum | cut -c1-32
}

same=0; diff=0
for t in .build-whim/q41.tar .build-whim/q82.tar .build-zero/r45.tar .build-zero/r0.tar; do
    [ -f "$t" ] || continue
    w=$(mktemp -d)
    tar xf "$t" -C "$w"
    a=$(shell_td "$w")
    b=$(./"$bin" treedigest "$w")
    if [ "$a" = "$b" ]; then
        same=$((same + 1)); printf '  %-22s same  %s\n' "$(basename "$t")" "$a"
    else
        diff=$((diff + 1)); printf '  %-22s DIFFER  shell=%s go=%s\n' "$(basename "$t")" "$a" "$b"
    fi
    rm -rf "$w"
done
echo "treedigest: $same same, $diff differ"
[ "$diff" -eq 0 ]
