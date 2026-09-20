#!/bin/sh
# `slimtools cmdidxs` against tools/create_cmdidxs.py, on every corpus file
# that HAS a command table.
#
# Usage: sh tools/gocmp/idxcmp.sh        (run from the repository root)
#
# Three outcomes are counted separately and the distinction is the point.  A
# file with no `// begin ex_cmdidxs.h` banners is not a failure and not a pass:
# whim's phase 80 took the derived index with the 489 stub rows, so every whim
# and zero boundary answers "no banners" and would otherwise be counted as
# agreement.  Only the files that really generate a table are evidence, and the
# run refuses if there are none of those.
set -eu

[ -d tools ] && [ -d pipes ] || { echo "idxcmp: run me from the repository root" >&2; exit 1; }
bin=$(sh tools/gobuild.sh)
corpus=${GOCMP_CORPUS:-.gocorpus}

same=0; differ=0; notable=0; checked=0
for f in "$corpus"/*/*.c; do
    [ -f "$f" ] || continue
    a=$("./$bin" cmdidxs "$f" 2>/dev/null || echo FAILED)
    b=$(python3 tools/create_cmdidxs.py "$f" 2>/dev/null || echo FAILED)
    if [ "$a" = FAILED ] && [ "$b" = FAILED ]; then
        notable=$((notable + 1))
        continue
    fi
    if [ "$a" = "$b" ]; then
        same=$((same + 1))
    else
        differ=$((differ + 1))
        echo "DIFFER generate: $f"
    fi
    # --check is a separate answer and worth its own comparison: it reads the
    # block already in the file, so the two can agree on what to GENERATE and
    # disagree on whether the file matches it.
    "./$bin" cmdidxs "$f" --check >/dev/null 2>&1 && ga=0 || ga=1
    python3 tools/create_cmdidxs.py "$f" --check >/dev/null 2>&1 && pa=0 || pa=1
    if [ "$ga" != "$pa" ]; then
        differ=$((differ + 1))
        echo "DIFFER --check: $f  go=$ga python=$pa"
    fi
    checked=$((checked + 1))
done

echo "idxcmp: $same same, $differ differ, $checked --check pairs, $notable with no table"
[ "$checked" -gt 0 ] || { echo "idxcmp: no file in $corpus has a command table - vacuous" >&2; exit 1; }
[ "$differ" -eq 0 ]
