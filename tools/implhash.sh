#!/bin/sh
# The identity of a phase's tier-2 implementation.
#
# Usage: tools/implhash.sh <phase>
#
# Half of a memoize key.  The other half is the input boundary; together they
# say "this implementation, applied to this input", which is the only thing a
# cached result is an answer to.
#
# What counts as the implementation is the phase's own program plus everything
# it names: the tools it calls, the patches it applies, the tables it reads,
# the templates it installs.  Extracting that by grepping the script for paths
# under tools/ is exact enough and keeps the invalidation narrow -- editing
# resolve.py should re-run phase 5, not all ten.  One level of indirection is
# followed, which covers canon.sh calling seven canonicalisers.
#
# A phase with no program has no implementation to hash, and prints the word
# `agent`: tier 1 is not cacheable, because it is not a function.
set -eu

phase=${1:?usage: implhash.sh <phase>}
prog="tools/phase$phase.sh"

[ -f "$prog" ] || { echo agent; exit 0; }

deps() {
    grep -oE 'tools/[A-Za-z0-9_/-]+\.(py|sh|txt|mk|patch)' "$1" 2>/dev/null || true
}

{
    cat "$prog"
    for d in $(deps "$prog" | sort -u); do
        [ -f "$d" ] || continue
        cat "$d"
        for e in $(deps "$d" | sort -u); do
            [ -f "$e" ] && cat "$e"
        done
    done
} | sha256sum | cut -c1-16
