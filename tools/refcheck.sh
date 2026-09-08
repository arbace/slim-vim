#!/bin/sh
# Compare a freshly produced vim.c against the previous pass's frozen copy.
#
# This is the end-to-end check the workflow buys: .reference/vim.c IS the last
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
if [ ! -f "$ref/vim.c" ]; then
    report source "absent from $ref/"
elif cmp -s vim.c "$ref/vim.c"; then
    compared=$((compared + 1))
    report source "identical -- $(grep -c '' vim.c) lines, byte for byte"
else
    compared=$((compared + 1))
    add=$(diff "$ref/vim.c" vim.c | grep -c '^>')
    del=$(diff "$ref/vim.c" vim.c | grep -c '^<')
    report source "differs -- +$add -$del lines against $(grep -c '' "$ref/vim.c")"
    fail=1
fi

# --- the binary, tier 1 ---------------------------------------------------
# Same file name or __FILE__ differs; pinned epoch or __DATE__/__TIME__ do.
if [ ! -f "$ref/vim" ]; then
    report binary "absent from $ref/"
else
    tmp=$(mktemp -d)
    cp vim.c "$tmp/vim.c"
    if ( cd "$tmp" && SOURCE_DATE_EPOCH=0 gcc -O0 -static -s -o vim vim.c 2>/dev/null ); then
        compared=$((compared + 1))
        if cmp -s "$tmp/vim" "$ref/vim"; then
            report binary "identical -- $(stat -c%s "$tmp/vim") bytes, tier 1"
        else
            report binary "differs -- $(stat -c%s "$tmp/vim") vs $(stat -c%s "$ref/vim") bytes"
            fail=1
        fi
    else
        report binary "BUILD FAILED"
        fail=1
    fi
    rm -rf "$tmp"
fi

# --- the documents and the makefile ---------------------------------------
same=; diffr=
for f in Makefile CLAUDE.md GOAL.md LICENSE; do
    if [ ! -f "$ref/$f" ]; then diffr="$diffr $f(absent)"
    elif cmp -s "$f" "$ref/$f"; then same="$same $f"
    else diffr="$diffr $f"; fi
done
[ -n "$same" ] && report unchanged "$(echo $same)"
[ -n "$diffr" ] && report changed "$(echo $diffr) -- expected if this pass edited them"

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
