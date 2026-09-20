#!/bin/sh
# dropoptions.py vs `slimtools dropoptions`, on real invocations against the
# boundary each phase was handed.  Both the successes and the three refusals.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0

try() {   # try <input.c> <args...>
    src=$1; shift
    a=$(mktemp); b=$(mktemp)
    cp "$src" "$a"; cp "$src" "$b"
    pa=$(python3 tools/dropoptions.py "$a" "$@" 2>&1 || echo "EXIT$?")
    pb=$(./"$bin" dropoptions "$b" "$@" 2>&1 || echo "EXIT$?")
    if [ "$pa" = "$pb" ] && cmp -s "$a" "$b"; then
        same=$((same + 1))
        printf '  %-28s same  %s\n' "$*" "$(echo "$pa" | head -1 | cut -c1-48)"
    else
        diff=$((diff + 1))
        printf '  %-28s DIFFER\npy: %s\ngo: %s\n' "$*" "$pa" "$pb"
        cmp -s "$a" "$b" || echo "  (and the files differ)"
    fi
    rm -f "$a" "$b"
}

W=${GOCMP_CORPUS:-.cache/gocorpus}/wz
# Real invocations, against a boundary where the rows still exist.
try "$W/whim-q0.c" --strict fileencodings termencoding
try "$W/whim-q0.c" --strict mouse mousefocus mousehide
try "$W/whim-q0.c" --strict spell spellcapcheck spellfile spelllang
try "$W/whim-q0.c" --strict --local readonly
try "$W/whim-q0.c" --strict --local fsync
# Refusals: a name that is not there, and a local option without --local.
try "$W/whim-q0.c" --strict no-such-option-9x
try "$W/whim-q0.c" --strict readonly
try "$W/zero-r45.c" --strict paste

echo "dropoptions: $same same, $diff differ"
[ "$diff" -eq 0 ]
