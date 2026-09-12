#!/bin/sh
# Phase 10 -- the forward declarations nothing needs.  See SLIM-GOAL.md.
#
# Usage: tools/slim10.sh <work-dir>      (run from the repository root)
#
# Phase 8 gave every symbol internal linkage.  This is the consequence: about
# half the forward declarations exist only because C wants a name in scope
# before its first use, and for a function nothing mentions until after its own
# definition they say nothing the compiler does not already know.
#
# THE HAZARD, and the reason this is a phase rather than a sed: A `static`
# DECLARATION IS NOT ONLY A DECLARATION.  A definition that follows one inherits
# internal linkage from it, which is why most definitions here do not say
# `static` themselves and are static anyway.  Delete such a prototype and the
# function silently becomes EXTERNAL -- nm grows a symbol, and this tree's whole
# claim is that main is the only one.  Nothing fails: the build is clean, the
# editor runs, and the check is a symbol table nobody looked at.
#
# So every dropped prototype hands `static` to its definition on the way out,
# and nm is checked below rather than trusted.
#
# This phase and the next were the pure pipeline's phases 7 and 8 for a while,
# which was the wrong home for them: neither removes a capability, and both are
# things that are true of a single translation unit whatever it contains.  They
# belong to whichever pipeline first has one.
set -eu

root=$(pwd)
work=${1:?usage: slim10.sh <work-dir>}
f="$work/vim.c"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

before=$(grep -c '' "$f")

python3 tools/dropprotos.py "$f" --delete

# --- the invariant this phase could silently break ------------------------
# nm the OBJECT: a static musl binary defines 1,400-odd symbols of its own and
# would bury the answer.
gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o "$tmp/o.o" "$f" 2>"$tmp/gcc.txt" || {
    echo "  compile      FAILED -- a dropped declaration was load-bearing"
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
    echo '               a dropped static declaration is a dropped linkage'
    exit 1
fi
echo "  linkage      nm on the object still prints exactly main"

( cd "$work" && sh "$root/tools/build.sh" "$tmp/vim.out" )
echo "  build        ok, $before -> $(grep -c '' "$f") lines"
