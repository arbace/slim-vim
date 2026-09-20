#!/bin/sh
# Every ported sweep/canonicaliser tool against every corpus, as a table.
#
# Usage: sh tools/gocmp/matrix.sh        (run from the repository root)
#
# THE CORPUS PATHS HERE WERE WRONG AND THE FAILURE MODE WAS SILENCE.  They read
# `tools/gocmp/gc/wz`, `tools/gocmp/gc/unswept` and `tools/gocmp/corpus-slim`,
# which is a layout no other script in this directory has used since the corpus
# moved; every one of the other eleven reads $GOCMP_CORPUS.  An unmatched glob
# is handed to difftest as a literal path, difftest finds no file, and the row
# prints a verdict that looks like agreement.  A table of fourteen tools times
# three corpora, all agreeing, having compared NOTHING.
#
# So this script now refuses a corpus it cannot find, before running anything.
# That is the same rule pcutcmp.sh enforces by counting real cuts separately
# from refusals: a comparison that cannot fail proves nothing, and the way a
# corpus-driven harness cannot fail is by having no corpus.
set -eu

[ -d tools ] && [ -d pipes ] || { echo "matrix: run me from the repository root" >&2; exit 1; }
bin=$(sh tools/gobuild.sh)
corpus=${GOCMP_CORPUS:-.gocorpus}

for c in wz unswept slim; do
    n=$(ls "$corpus/$c"/*.c 2>/dev/null | wc -l)
    [ "$n" -gt 0 ] || {
        echo "matrix: $corpus/$c holds no .c -- build it with tools/gocorpus.sh" >&2
        exit 1
    }
    printf 'corpus %-8s %s files\n' "$c" "$n"
done
echo

for t in deadsweep deadprotos typereach funcreach deadfields deadenums \
         blankruns joinparens splitheads brace onestmt onedecl forcomma canon; do
    for c in wz unswept slim; do
        r=$("./$bin" difftest "$t" "$corpus/$c"/*.c 2>&1 | head -1 | sed 's/.*: //')
        printf '%-11s %-9s %s\n' "$t" "$c" "$r"
    done
done
