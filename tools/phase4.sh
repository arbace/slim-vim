#!/bin/sh
# Phase 4 -- the cheap line-level normalisations.  See GOAL.md.
#
# Usage: tools/phase4.sh <work-dir>       (run from the repository root)
#
# Three passes over every source, in this order, none of which understands C:
# splice out backslash continuations, expand tabs at the 8-column stops they
# were written for, drop every comment.  The tools already exist and are the
# whole of the phase; what is here is the ordering and the two checks.
#
# The check that matters is the blank-line count, and it is the one thing
# neither verification tier can see.  A comment-removal pass that collapses
# multi-line comments onto one line passes tier 1 AND tier 2 -- byte-identical
# binary, identical token stream -- while destroying the paragraphing that
# separates every function from the next.  It happened: 26,476 blank lines down
# to 3,884, with both checks green.  decomment.py replaces a comment with one
# space plus the newlines it spanned, so line i of the output is line i of the
# input and the count cannot move.  Requiring that here is what turns a
# property of the tool into a property of the pass.
set -eu

work=${1:?usage: phase4.sh <work-dir>}
jobs=$(nproc 2>/dev/null || echo 4)

files=$(ls "$work"/*.c "$work"/*.h "$work"/proto/*.pro 2>/dev/null)
[ -n "$files" ] || { echo "  phase4       no sources in $work"; exit 1; }

blanks() { cat $files | grep -c '^[ 	]*$' || true; }

# Splicing is translation phase 2 and cannot change the token stream -- unless
# there is whitespace between a backslash and its newline, which is not a
# continuation at all and would have the splice eat a real line.
stray=$(grep -lE '\\[ 	]+$' $files || true)
if [ -n "$stray" ]; then
    echo "  splice       REFUSED -- trailing whitespace after a backslash in:"
    echo "$stray" | sed 's/^/                 /'
    exit 1
fi

before=$(blanks)

python3 tools/splice.py $files
python3 tools/untab.py $files
python3 tools/decomment.py $files

after=$(blanks)
if [ "$before" != "$after" ]; then
    echo "  blanks       LOST -- $before before, $after after."
    echo "               Neither verification tier can see this: a pass that"
    echo "               collapses comments onto one line is byte-identical and"
    echo "               token-identical and still destroys the paragraphing."
    exit 1
fi
echo "  blanks       $after, unmoved -- the paragraphing survived"

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" -j"$jobs" >/dev/null 2>&1; then
    echo "  build        ok, with no comments and no tabs"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
