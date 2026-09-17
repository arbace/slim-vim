#!/bin/sh
# The identity of a phase's tier-2 implementation.
#
# Usage: tools/implhash.sh <unit> [pipeline]      a phase N, or a stage A-B
#
# Half of a memoize key.  The other half is the input boundary; together they
# say "this implementation, applied to this input", which is the only thing a
# cached result is an answer to.
#
# What counts as the implementation is the phase's own program -- or its edit and
# check parts, see tools/phaserun.sh -- plus everything
# it names: the tools it calls, the patches it applies, the tables it reads,
# the templates it installs.  Extracting that by grepping the script for paths
# under tools/ and pipes/ is exact enough and keeps the invalidation narrow -- editing
# resolve.py should re-run phase 5, not all ten.  One level of indirection is
# followed, which covers canon.sh calling seven canonicalisers.
#
# A phase with no program has no implementation to hash, and prints the word
# `agent`: tier 1 is not cacheable, because it is not a function.
set -eu

phase=${1:?usage: implhash.sh <unit> [pipeline]}
. tools/pipeline.sh "${2:-slim}"
progs=$(tools/phaserun.sh --parts "$PIPE" "$phase")

[ -n "$progs" ] || { echo agent; exit 0; }

deps() {
    grep -oE '(tools|pipes)/[A-Za-z0-9_/-]+\.(py|sh|txt|mk|patch)' "$1" 2>/dev/null || true
}

# A split phase's implementation is both parts and what tools/phaserun.sh runs
# between and before them -- the sweep and the symbol snapshot -- which the
# programs no longer name.  Those are level-one names, as they were when every
# program named tools/sweep.sh itself, so the sweep's own tools are still hashed.
# A whole program hashes exactly as it always did.
driven() {
    case $progs in *-edit.sh*) ;; *) return 0 ;; esac
    echo tools/phaserun.sh
    echo tools/sweep.sh
    echo tools/symbols.sh
}

{
    for p in $progs; do cat "$p"; done
    for d in $( { for p in $progs; do deps "$p"; done; driven; } | sort -u); do
        [ -f "$d" ] || continue
        cat "$d"
        for e in $(deps "$d" | sort -u); do
            [ -f "$e" ] && cat "$e"
        done
    done
} | sha256sum | cut -c1-16
