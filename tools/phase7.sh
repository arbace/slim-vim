#!/bin/sh
# Phase 7 -- canonicalise, before anything reads C syntax.  See GOAL.md.
#
# Usage: tools/phase7.sh <work-dir>       (run from the repository root)
#
# Seven passes, run to a joint fixpoint by tools/canon.sh: collapse blank runs,
# join parenthesised groups onto one line, split control-statement heads, brace
# every body, one statement per line, one declarator per declaration, hoist
# comma operators out of `for` init clauses.
#
# Every one of them is pure formatting, which means the check is tier 1 -- the
# binary is byte-identical or something changed that was not formatting.  That
# is the cheapest verification there is and it is available only because three
# things were arranged much earlier: no __LINE__ anywhere (the asserts went in
# Phase 0), no -g, and a pinned SOURCE_DATE_EPOCH, which tools/build.sh does.
#
# The baseline binary is built BEFORE anything is touched.  Building it after
# would compare the result against itself.
set -eu

work=${1:?usage: phase7.sh <work-dir>}
root=$(pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- tier 1's left-hand side, before any change ---------------------------
( cd "$work" && sh "$root/tools/build.sh" "$tmp/vim.base" )
echo "  baseline     $(stat -c%s "$tmp/vim.base") bytes, SOURCE_DATE_EPOCH pinned"

before=$(grep -c '' "$work/vim.c")

# --- the seven passes, to a fixpoint --------------------------------------
tools/canon.sh "$work/vim.c"

after=$(grep -c '' "$work/vim.c")
blank=$(grep -c '^[ 	]*$' "$work/vim.c" || true)
echo "  canonical    $before -> $after lines, $blank blank"

# --- tier 1 ---------------------------------------------------------------
( cd "$work" && sh "$root/tools/build.sh" "$tmp/vim.after" )
if cmp -s "$tmp/vim.base" "$tmp/vim.after"; then
    echo "  tier 1       byte-identical -- nothing but formatting moved"
else
    echo "  tier 1       DIFFERS -- a canonicaliser changed the program."
    echo "               Formatting cannot do that, so one of the seven has a"
    echo "               bug; bisect by running them one at a time."
    exit 1
fi

# --- the two things tier 1 cannot see -------------------------------------
# A brace pass that works makes -Wmisleading-indentation structurally unable to
# fire, and the command table is where a stray re-indent shows up first.
mis=$(gcc -fsyntax-only -Wmisleading-indentation "$work/vim.c" 2>&1 \
        | grep -c 'misleading-indentation' || true)
if [ "$mis" != 0 ]; then
    echo "  indentation  $mis warnings -- every body should be a brace block"
    exit 1
fi
python3 tools/create_cmdidxs.py "$work/vim.c" --check
echo "  canary       command table regenerates byte for byte"
