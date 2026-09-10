#!/bin/sh
# Phase 9 -- SYNTHESISED from a tier-1 run.  See GOAL.md for what the
# phase means; this file only reproduces what an agent did once.
#
# Usage: tools/phase9.sh <work-dir>
#
# This is tier 2 in its degenerate form: a patch, and nothing else.  It is
# correct for the input it was recorded from and it will fail on any upstream
# that edits a line it touches -- at which point the memoize falls through to
# tier 1, which produces a new answer and a new patch.
#
# The work is to make the patch smaller.  Replace a hunk with the rule that
# produces it -- a computed set, a table, a transformation over every line of a
# shape -- and leave only what is genuinely a decision.  tools/residue.sh
# reports where each phase stands.
set -eu

work=${1:?usage: phase9.sh <work-dir>}

if ! patch -p1 -d "$work" --forward --silent < tools/patches/p9-residue.patch; then
    echo "  patch        p9 residue no longer applies -- upstream moved under it"
    exit 1
fi
echo "  patch        p9 residue applied, 72043 lines"
