#!/bin/sh
# Phase 11 -- every definition says its own linkage.  See SLIM-GOAL.md.
#
# Usage: tools/slim11.sh <work-dir>      (run from the repository root)
#
# After phase 10 there are still definitions that are static only because a
# declaration earlier in the file said so and a definition that follows one
# inherits its internal linkage.  That works, and it is a trap with a long fuse:
# delete the declaration -- for being redundant, for tidiness, by accident --
# and the function quietly acquires external linkage.  Nothing fails.  The build
# is clean, the editor runs, and nm grows a symbol that this tree's central
# claim says cannot exist.
#
# Phase 10 met that trap and worked around it, handing `static` to each
# definition whose declaration it removed.  This finishes the job from the other
# end: every definition says what its linkage is, and no declaration anywhere is
# load-bearing for anything but order.  After it, a prototype can be removed for
# being unnecessary without anyone having to think about linkage at all.
#
# `main` is the exception and the only one -- it is the program's entry point and
# the one symbol that is meant to be external.  The nm check is what proves that
# is still true.
set -eu

root=$(pwd)
work=${1:?usage: slim11.sh <work-dir>}
f="$work/vim.c"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

before=$(grep -c '' "$f")

python3 tools/allstatic.py "$f" --delete

gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o "$tmp/o.o" "$f" 2>"$tmp/gcc.txt" || {
    echo "  compile      FAILED"
    grep -m5 'error:' "$tmp/gcc.txt" | sed 's/^/               /'
    exit 1
}
warn=$(grep 'warning:' "$tmp/gcc.txt" | grep -cv 'implicit-fallthrough' || true)
if [ "$warn" != 0 ]; then
    echo "  warnings     $warn besides the fall-throughs"
    grep 'warning:' "$tmp/gcc.txt" | grep -v 'implicit-fallthrough' | head -5 \
        | sed 's/^/               /'
    exit 1
fi
ext=$(nm --extern-only --defined-only "$tmp/o.o" | awk '{print $NF}' | grep -v '^main$' || true)
if [ -n "$ext" ]; then
    echo "  linkage      these became external: $ext"
    exit 1
fi
echo "  linkage      nm on the object still prints exactly main"

( cd "$work" && sh "$root/tools/build.sh" "$tmp/vim.out" )
echo "  build        ok, $before -> $(grep -c '' "$f") lines"
