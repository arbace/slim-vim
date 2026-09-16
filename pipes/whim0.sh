#!/bin/sh
# Whim phase 0 -- seed, and prove the copy is a copy.  See WHIM-GOAL.md.
#
# Usage: pipes/whim0.sh <work-dir>       (run from the repository root)
#
# whim-vim.c begins as slim-vim.c and this phase's only job is to establish
# that.  It matters because every phase after it is measured as a delta: if the
# seed is not identical, every later report is against the wrong thing, and the
# error would look like whatever that phase happened to do.
#
# There is nothing here to make faster.  It is a `cmp` and a build, and it
# exists so that the first boundary means something.
set -eu

work=${1:?usage: whim0.sh <work-dir>}
f="$work/whim-vim.c"

if ! cmp -s "$f" slim-vim.c; then
    echo "  seed         DIFFERS from slim-vim.c -- the pipeline's input is not"
    echo "               what it claims, and every later delta would be measured"
    echo "               against the wrong file."
    exit 1
fi
echo "  seed         identical to slim-vim.c, $(grep -c '' "$f") lines"

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $(stat -c%s "$work/whim-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
