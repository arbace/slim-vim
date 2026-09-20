#!/bin/sh
# retire.py and droplocal.py vs their Go subcommands, on real invocations and
# on their refusals.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0

try() {   # try <tool> <input.c> <args...>
    tool=$1; src=$2; shift 2
    a=$(mktemp); b=$(mktemp)
    cp "$src" "$a"; cp "$src" "$b"
    pa=$(python3 "tools/$tool.py" "$a" "$@" 2>&1 || echo "EXIT$?")
    pb=$(./"$bin" "$tool" "$b" "$@" 2>&1 || echo "EXIT$?")
    if [ "$pa" = "$pb" ] && cmp -s "$a" "$b"; then
        same=$((same + 1)); printf '  %-10s %-24s same  %s\n' "$tool" "$*" "$(echo "$pa" | head -1 | cut -c1-40)"
    else
        diff=$((diff + 1)); printf '  %-10s %-24s DIFFER\npy: %s\ngo: %s\n' "$tool" "$*" "$pa" "$pb"
        cmp -s "$a" "$b" || echo "  (and the files differ)"
    fi
    rm -f "$a" "$b"
}

W=${GOCMP_CORPUS:-.gocorpus}/wz
try retire "$W/whim-q0.c" gui gvim
try retire "$W/whim-q0.c" shell terminal
try retire "$W/whim-q0.c" no-such-command-9x
try retire "$W/whim-q41.c" gui
try droplocal "$W/whim-q0.c" b_p_bin
try droplocal "$W/whim-q0.c" no_such_field_9x
try droplocal "$W/whim-q0.c" b_p_ro

echo "retire/droplocal: $same same, $diff differ"
[ "$diff" -eq 0 ]
