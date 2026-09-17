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

# --edit N: the identity of phase N's EDIT part alone, and what it names -- the key
# tools/phaserun.sh caches that edit's result under inside a stage.
if [ "${1:-}" = "--edit" ]; then
    phase=${2:?usage: implhash.sh --edit <phase> [pipeline]}
    . tools/pipeline.sh "${3:-slim}"
    progs=$(tools/phaserun.sh --parts "$PIPE" "$phase" | grep -- '-edit\.sh$' || true)
    [ -n "$progs" ] || { echo "implhash: phase $phase has no edit part" >&2; exit 1; }
    edit_only=1
else
    phase=${1:?usage: implhash.sh <unit> [pipeline]}
    . tools/pipeline.sh "${2:-slim}"
    progs=$(tools/phaserun.sh --parts "$PIPE" "$phase")
fi

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
    [ -z "${edit_only:-}" ] || return 0
    case $progs in *-edit.sh*) ;; *) return 0 ;; esac
    echo tools/phaserun.sh
    echo tools/sweep.sh
    echo tools/symbols.sh
}

# The declared delta is data: the driver checks it after a stage, and phase 80's
# edit reads its table cut from it.  What is hashed is the lines of
# pipes/<pipeline>.delta for the unit's phases and every phase before them (for
# --edit, the phase's own lines) -- not the whole file, so declaring a new phase's
# delta at the end moves no earlier key -- and, for a unit, the pipeline's checker
# (PDELTA, tools/whimdelta.sh or tools/zerodelta.sh) with what it names.
delta_lines() {
    [ -f "pipes/$IMPL.delta" ] || return 0
    case $progs in *-edit.sh*) ;; *) return 0 ;; esac
    awk -v N="${phase#*-}" -v ONLY="${edit_only:-}" '
        /^[ \t]*#/ || NF == 0 { next }
        /^[0-9]/ { p = $1 + 0 }
        p <= N && (ONLY == "" || p == N) { print }' "pipes/$IMPL.delta"
    if [ -z "${edit_only:-}" ]; then
        cat "$PDELTA"
        for e in $(deps "$PDELTA" | sort -u); do [ -f "$e" ] && cat "$e"; done
    fi
}

{
    for p in $progs; do cat "$p"; done
    delta_lines
    for d in $( { for p in $progs; do deps "$p"; done; driven; } | sort -u); do
        [ -f "$d" ] || continue
        cat "$d"
        for e in $(deps "$d" | sort -u); do
            [ -f "$e" ] && cat "$e"
        done
    done
} | sha256sum | cut -c1-16
