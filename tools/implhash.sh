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

# A program's dependencies are the paths it NAMES, and a DIRECTORY it names
# expands to every file under it.
#
# THE DIRECTORY CASE IS THE FIX FOR A MEASURED HOLE, not a convenience.  The
# extension list had no `go`, so when tools/sweep.sh and tools/canon.sh became
# wrappers onto a Go binary the whole sweep fell out of every key.  Measured on
# whim 13-41, each with the control that says the test can fail:
#
#   baseline                                   5167f16765693870
#   edit tools/go/internal/sweep/sweep.go      5167f16765693870   does NOT move
#   edit tools/sweep.sh            (control)   0686fde7f17aa479   moves
#   edit tools/patches/cc-v4-c23.patch         5167f16765693870   does NOT move
#   edit tools/gobuild.sh          (control)   752c38dcf30160fb   moves
#
# gobuild.sh built a different binary across the first edit, so the
# implementation changed, the binary changed, and the memoize could not tell: a
# warm repass would replay a boundary produced by a different sweep and report
# success.  That is the `cutil.py`/`macros.py` hazard CLAUDE.md records, at the
# scale of the whole sweep and the whole canonicaliser.
#
# The patch was invisible for a SECOND reason and it is worth separating: this
# function is applied twice, so a program reaches its own names and theirs, and
# no further.  sweep.sh is level 1 (driven() names it), gobuild.sh is level 2,
# and the patch gobuild.sh names is level 3.  Naming the patch in the wrappers
# themselves is what brings it to level 2; no change here would have.
#
# A LIST OF THE FILES THAT MATTER IS THE ARTIFACT THAT FAILED.  The wrappers
# named 18 of 128 .go files, and four the sweep certainly reaches -- body.go,
# definition.go, split.go, strings.go -- were in neither list.  So the rule is
# the directory and not a curation of it: gobuild.sh already keys the binary on
# go.mod, go.sum, the patch and every .go sorted, and expanding tools/go/ makes
# this the same set.  Two computed traversals of one tree cannot drift; two
# hand-maintained lists of it did.
#
# EVERY FILE UNDER THE DIRECTORY, with no name filter, and that is deliberate.
# A filter is another curated list and can drop a real dependency, which makes
# a wrong answer possible.  Taking everything can only admit a file that should
# not be there -- an untracked build artifact under tools/go/ would enter the
# key and make two checkouts of one commit disagree, which costs a rebuild and
# never an incorrect boundary.  An over-inclusive key costs CPU; an
# under-inclusive key costs correctness.  (`go build -trimpath -o .cache/...`
# keeps output out of the tree; `go test` writing a binary in place would not.)
#
# The cost is deliberate and belongs in the open: internal/harness/ and
# internal/cut/ are hashed too, though neither is wired into a pipeline today,
# so editing a dormant cutter re-runs every phase.
deps() {
    grep -oE '(tools|pipes)/[A-Za-z0-9_/-]+\.(py|sh|txt|mk|patch|go|mod|sum)' "$1" 2>/dev/null || true
    # A bare directory mention: `tools/go/` matches, and `tools/patches/x.patch`
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
