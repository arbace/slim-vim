#!/bin/sh
# What pure-vim costs a target: bytes to store, and symbols to provide.
#
# Usage: tools/purescore.sh
#
# PURE-GOAL.md measures phases against these two together, and the second is
# the one that matters.  An embedded target is defined by what it must supply,
# not by what it costs to store, so a phase that shrinks the binary while
# adding a libc call has gone backwards -- and only a report that shows both
# can say so.
#
# slim-vim is shown beside it because every number here is a delta from it.
set -eu

row() {
    name=$1; src=$2; bin=$3
    [ -f "$src" ] || { printf '  %-10s %s\n' "$name" "absent"; return; }
    if [ ! -f "$bin" ]; then
        ( cd "$(dirname "$src")" >/dev/null 2>&1 || true
          gcc -O0 -static -s -o "$bin" "$src" 2>/dev/null ) || true
    fi
    lines=$(grep -c '' "$src")
    bytes=$([ -f "$bin" ] && stat -c%s "$bin" || echo 0)
    # What it needs from the world: undefined symbols in the object, which is
    # the honest question.  A static binary has resolved them all already, so
    # asking the binary would answer "none" and mean nothing.
    obj=$(mktemp).o
    gcc -c -O0 -o "$obj" "$src" 2>/dev/null || true
    syms=$(nm -u "$obj" 2>/dev/null | awk '{print $NF}' | sort -u | grep -c . || true)
    rm -f "$obj"
    printf '  %-10s %9s lines  %11s bytes  %4s libc symbols\n' \
        "$name" \
        "$(echo "$lines" | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta')" \
        "$(echo "$bytes" | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta')" \
        "$syms"
}

row slim-vim slim-vim.c slim-vim
row pure-vim pure-vim.c pure-vim
