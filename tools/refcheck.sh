#!/bin/sh
# Compare a freshly produced slim-vim.c against the previous pass's frozen copy.
#
# This is the end-to-end check the workflow buys: .reference/slim-vim.c IS the last
# pass's output, so a new one should differ only by what upstream changed --
# for a tiny build, usually nothing at all.
#
# .reference/ is gitignored and deliberately optional.  A tree cloned fresh, or
# a first pass, will not have one; that is not a failure and not an excuse to
# skip the rest of the verification either.  Say so and move on.
#
# Usage: tools/refcheck.sh [reference-dir]        (default: .reference)

set -u
ref=${1:-.reference}

if [ ! -d "$ref" ]; then
    echo "reference     absent -- $ref/ does not exist, nothing to compare"
    echo "              (expected on a first pass; verify.sh still applies)"
    exit 0
fi

fail=0
compared=0
report() { printf '  %-12s %s\n' "$1" "$2"; }

# --- the source -----------------------------------------------------------
if [ ! -f "$ref/slim-vim.c" ]; then
    report source "absent from $ref/"
elif cmp -s slim-vim.c "$ref/slim-vim.c"; then
    compared=$((compared + 1))
    report source "identical -- $(grep -c '' slim-vim.c) lines, byte for byte"
else
    compared=$((compared + 1))
    add=$(diff "$ref/slim-vim.c" slim-vim.c | grep -c '^>')
    del=$(diff "$ref/slim-vim.c" slim-vim.c | grep -c '^<')
    report source "differs -- +$add -$del lines against $(grep -c '' "$ref/slim-vim.c")"
    fail=1
fi

# --- the binary, tier 1 ---------------------------------------------------
# Same file name or __FILE__ differs; pinned epoch or __DATE__/__TIME__ do.
if [ ! -f "$ref/slim-vim" ]; then
    report binary "absent from $ref/"
else
    tmp=$(mktemp -d)
    cp slim-vim.c "$tmp/slim-vim.c"
    if ( cd "$tmp" && SOURCE_DATE_EPOCH=0 gcc -O0 -static -s -o slim-vim slim-vim.c 2>/dev/null ); then
        compared=$((compared + 1))
        if cmp -s "$tmp/slim-vim" "$ref/slim-vim"; then
            report binary "identical -- $(stat -c%s "$tmp/slim-vim") bytes, tier 1"
        else
            report binary "differs -- $(stat -c%s "$tmp/slim-vim") vs $(stat -c%s "$ref/slim-vim") bytes"
            fail=1
        fi
    else
        report binary "BUILD FAILED"
        fail=1
    fi
    rm -rf "$tmp"
fi

# There is no comparison of the documents or the makefile.  It used to report
# them "changed -- expected if this pass edited them", which could never fail
# and was true of every pass, and the copies it read were a snapshot whose age
# nothing showed.  They are tracked: `git diff` is the honest comparison.

# --- the baselines --------------------------------------------------------
if [ -d "$ref/baselines" ]; then
    report baselines "present -- run: tools/verify.sh $ref/baselines --enums"
else
    report baselines "absent -- nothing to check behaviour against"
fi

if [ "$compared" = 0 ]; then
    echo "  reference    nothing compared -- no source or binary in $ref"
elif [ "$fail" = 0 ]; then
    echo "  reference    matches"
else
    echo "  reference    DIFFERS -- explain every line above before committing"
fi
exit $fail
