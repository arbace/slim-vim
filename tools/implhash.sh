#!/bin/sh
# The identity of a phase's tier-2 implementation.
#
# Usage: tools/implhash.sh <phase> [pipeline]
#
# Half of a memoize key.  The other half is the input boundary; together they
# say "this implementation, applied to this input", which is the only thing a
# cached result is an answer to.
#
# What counts as the implementation is the phase's own program -- see
# tools/phaserun.sh -- plus everything
# it names: the tools it calls, the patches it applies, the tables it reads,
# the templates it installs.  Extracting that by grepping the script for paths
# under tools/ and pipes/ is exact enough and keeps the invalidation narrow -- editing
# resolve.py should re-run phase 5, not all ten.  One level of indirection is
# followed, which covers canon.sh calling seven canonicalisers.
#
# A phase with no program has no implementation to hash, and prints the word
# `agent`: tier 1 is not cacheable, because it is not a function.
set -eu

phase=${1:?usage: implhash.sh <phase> [pipeline]}
. tools/pipeline.sh "${2:-slim}"
progs=$(tools/phaserun.sh --parts "$PIPE" "$phase")

[ -n "$progs" ] || { echo agent; exit 0; }

# A program's dependencies are the paths it NAMES, and a DIRECTORY it names
# expands to every file under it -- with no name filter, deliberately: a filter
# is another curated list and can drop a real dependency, while taking
# everything can only admit a file that should not be there.  An over-inclusive
# key costs CPU; an under-inclusive one costs correctness.  (The directory rule
# was written for the Go toolset of the whim and zero pipelines, which moved to
# github.com/arbace/go-whim; a curated list of 18 of its 128 files had let the
# whole sweep fall out of every key.)
deps() {
    grep -oE '(tools|pipes)/[A-Za-z0-9_/-]+\.(py|sh|txt|mk|patch)' "$1" 2>/dev/null || true
    # A bare directory mention: `tools/patches/` matches, and `tools/patches/x.patch`
    # does not, because the character after the slash must not continue a path.
    # Files are emitted, never the directory, so the caller's `[ -f ]` guards
    # and its second level keep working unchanged.
    grep -oE '(tools|pipes)/[A-Za-z0-9_/-]*/([^A-Za-z0-9_/.-]|$)' "$1" 2>/dev/null |
        sed 's#[^/]$##' | sort -u |
        while read -r d; do
            [ -d "$d" ] && find "$d" -type f
        done | LC_ALL=C sort
    true
}

# Every slim phase is one whole program: hash it, then what it names, then what
# those name.
{
    for p in $progs; do cat "$p"; done
    for d in $( { for p in $progs; do deps "$p"; done; } | sort -u); do
        [ -f "$d" ] || continue
        cat "$d"
        for e in $(deps "$d" | sort -u); do
            [ -f "$e" ] && cat "$e"
        done
    done
} | sha256sum | cut -c1-16
