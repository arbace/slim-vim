#!/bin/sh
# What each product costs a target: bytes to store, and symbols to provide.
#
# Usage: tools/score.sh
#
# WHIM-GOAL.md measures phases against these two together, and the second is
# the one that matters.  An embedded target is defined by what it must supply,
# not by what it costs to store, so a phase that shrinks the binary while
# adding a libc call has gone backwards -- and only a report that shows both
# can say so.
#
# slim-vim is shown beside it because every number here is a delta from it.
set -eu

row() {
    name=$1; src=$2; bin=$3; ldflags=${4:--static -s}; cflags=${5:--O0}
    [ -f "$src" ] || { printf '  %-10s %s\n' "$name" "absent"; return; }
    # BUILD WHEN THE BINARY IS MISSING **OR OLDER THAN THE SOURCE**.  Testing only
    # for absence reports the bytes of whatever was lying about: measured, after
    # zero phases 14-16 this printed 799,816 for a source that builds to 805,544,
    # because the binary on disk predated them by eight hours.  The lines and the
    # symbols were right -- both are recomputed from the source below -- so the one
    # stale column was the plausible-looking one.  That is CLAUDE.md's "a clean
    # rebuild is byte-identical check passes if the rebuild never happened", in the
    # place that reports the number rather than the place that checks it.
    if [ ! -f "$bin" ] || [ "$src" -nt "$bin" ]; then
        ( cd "$(dirname "$src")" >/dev/null 2>&1 || true
          gcc $cflags $ldflags -o "$bin" "$src" 2>/dev/null ) || true
    fi
    lines=$(grep -c '' "$src")
    bytes=$([ -f "$bin" ] && stat -c%s "$bin" || echo 0)
    # What it needs from the world: undefined symbols in the object, which is
    # the honest question.  A static binary has resolved them all already, so
    # asking the binary would answer "none" and mean nothing.
    obj=$(mktemp).o
    gcc -c $cflags -o "$obj" "$src" 2>/dev/null || true
    syms=$(nm -u "$obj" 2>/dev/null | awk '{print $NF}' | sort -u | grep -c . || true)
    rm -f "$obj"
    printf '  %-10s %9s lines  %11s bytes  %4s libc symbols\n' \
        "$name" \
        "$(echo "$lines" | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta')" \
        "$(echo "$bytes" | sed -e :a -e 's/\(.*[0-9]\)\([0-9]\{3\}\)/\1,\2/;ta')" \
        "$syms"
}

row slim-vim slim-vim.c slim-vim
row whim-vim whim-vim.c whim-vim
# zero's compile line is its own: -no-pie from the seed, -fno-stack-protector from
# phase 1.  zero.mk states it once, as ZEROCFLAGS and ZEROLDFLAGS, and `make score`
# passes both; the defaults here are for a run by hand.  The flags are applied to the
# object as well as the binary, because __stack_chk_fail is a symbol the default
# CFLAGS put there.
row zero-vim zero-vim.c zero-vim "${ZEROLDFLAGS:--static -no-pie -s}" "${ZEROCFLAGS:--O0 -fno-stack-protector}"
