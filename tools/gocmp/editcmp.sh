#!/bin/sh
# Does a ported edit print what the heredoc printed?
#
# Usage: tools/gocmp/editcmp.sh <pipeline> <phase> <rev>   (from the repo root)
#   e.g. tools/gocmp/editcmp.sh whim 59 HEAD~4
#
# THE BOUNDARY GATES THE TREE AND NOTHING GATES THE REPORT.  A phase program's
# stdout is written to the pass log and read by a human comparing two phase
# commits; no check reads it, no digest covers it, and no recording contains it.
# So a port that transforms the tree correctly and prints the wrong thing passes
# every gate this tree has.  Found by making the mistake: whim59's tag is
# `nocompletion` and the port said `nowildcomp`, which the boundary could not
# see and would have shipped.
#
# This is the missing half.  <rev> is a commit where the phase still had its
# heredoc; the script restores the phase's input boundary, runs the OLD program
# and the NEW one on separate copies of it, and compares BOTH the tree and the
# report, line for line.
#
# WHY BOTH AND NOT JUST THE REPORT.  Comparing only the report would pass for a
# port that printed the right words having done something else; comparing only
# the tree is what we already have.  Together they say the port did the same
# thing and said the same thing.
#
# AND IT REFUSES RATHER THAN PASSING VACUOUSLY, which is this directory's one
# rule: the old program must contain a heredoc (or there is nothing to compare
# against), the new one must not, and the report must be non-empty (a phase that
# prints nothing would otherwise compare equal to anything).
set -eu

pipe=${1:?usage: editcmp.sh <pipeline> <phase> <rev>}
phase=${2:?usage: editcmp.sh <pipeline> <phase> <rev>}
rev=${3:?usage: editcmp.sh <pipeline> <phase> <rev>}

. tools/pipeline.sh "$pipe"

prog=pipes/$IMPL$phase-edit.sh
[ -f "$prog" ] || { echo "editcmp: no $prog" >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

old=$tmp/old-prog.sh
git show "$rev:$prog" > "$old" 2>/dev/null || { echo "editcmp: $prog does not exist at $rev" >&2; exit 2; }

grep -q "python3 -" "$old" || {
    echo "editcmp: $prog at $rev has no heredoc, so there is nothing to compare against" >&2
    exit 2
}
if grep -q "python3 -" "$prog"; then
    echo "editcmp: $prog still has a heredoc -- nothing has been ported" >&2
    exit 2
fi

# The phase's input is the boundary before its STAGE, which is the tree the
# driver really hands it.  Falling back to the phase's own number is wrong for a
# staged pipeline and would compare against a tree that never exists.
first=$(awk -v p="$phase" '
    /^stage /{ u = $2; a = u; b = u
               if (index(u, "-")) { split(u, f, "-"); a = f[1]; b = f[2] }
               if (p + 0 >= a + 0 && p + 0 <= b + 0) { print a; exit } }' "pipes/$IMPL.stages")
[ -n "$first" ] || { echo "editcmp: $phase is in no stage" >&2; exit 2; }

if [ "$first" = 0 ]; then in_tar=$PBUILD/input.tar; else in_tar=$PBUILD/$TAG$((first - 1)).tar; fi
[ -f "$in_tar" ] || { echo "editcmp: no $in_tar -- run a pass first" >&2; exit 2; }

# A PHASE'S REAL INPUT IS THE EARLIER PHASES OF ITS STAGE, NOT THE STAGE'S
# BOUNDARY, and getting that wrong is how this script first reported a defect
# that was its own: whim56's anchors do not match q41 because phases 42 to 55
# have not run, so the comparison refused and blamed the port.  A stage's input
# tar is the tree the FIRST phase sees; every later one sees what its
# predecessors left.  So the earlier phases run from <rev> -- their programs as
# they were when the heredoc still existed -- and only then does the phase under
# test run, twice.
prepare() {
    rm -rf "$tmp/w"; mkdir -p "$tmp/w" "$tmp/s"
    tools/restore.sh "$in_tar" "$tmp/w" >/dev/null
    i=$first
    while [ "$i" -lt "$phase" ]; do
        e=pipes/$IMPL$i-edit.sh
        if git show "$rev:$e" > "$tmp/pre.sh" 2>/dev/null; then
            sh "$tmp/pre.sh" "$tmp/w" "$tmp/s" >/dev/null 2>&1 ||
                { echo "editcmp: $e (at $rev) refused while preparing the input" >&2; exit 2; }
        fi
        i=$((i + 1))
    done
    cp -a "$tmp/w" "$tmp/base"; cp -a "$tmp/s" "$tmp/basestate"
}

# REFUSALS ARE COMPARED AS CAREFULLY AS SUCCESSES.  Exiting on the first
# non-zero status would hide the case where both refuse identically -- which is
# a real comparison of a rich diagnostic -- and would report the port as broken
# when it is faithful.  The status is part of what is compared.
run() {
    p=$1; out=$2
    rm -rf "$tmp/w" "$tmp/s"; cp -a "$tmp/base" "$tmp/w"; cp -a "$tmp/basestate" "$tmp/s"
    sh "$p" "$tmp/w" "$tmp/s" > "$out" 2>&1; echo "$?" > "$out.rc"
    cp "$tmp/w/$PSOURCE" "$out.c"
}

prepare
run "$old" "$tmp/py"
run "$prog" "$tmp/go"

rc=0
pyrc=$(cat "$tmp/py.rc"); gorc=$(cat "$tmp/go.rc")
if [ "$pyrc" != "$gorc" ]; then
    echo "  editcmp      $pipe $phase EXIT STATUS DIFFERS: python $pyrc, go $gorc"; rc=1
elif [ "$pyrc" != 0 ]; then
    printf '  editcmp      %s %-4s both REFUSED with status %s -- a refusal compared, not a pass\n' "$pipe" "$phase" "$pyrc"
fi
if cmp -s "$tmp/py.c" "$tmp/go.c"; then
    printf '  editcmp      %s %-4s tree IDENTICAL, %s lines\n' "$pipe" "$phase" "$(grep -c '' "$tmp/go.c")"
else
    echo "  editcmp      $pipe $phase TREES DIFFER:"; diff "$tmp/py.c" "$tmp/go.c" | head -20; rc=1
fi

n=$(grep -c '' "$tmp/py" || true)
[ "$n" -gt 0 ] || { echo "editcmp: the old program printed nothing, so the report comparison is vacuous" >&2; exit 2; }

if cmp -s "$tmp/py" "$tmp/go"; then
    printf '  editcmp      %s %-4s report IDENTICAL, %s lines\n' "$pipe" "$phase" "$n"
else
    echo "  editcmp      $pipe $phase REPORTS DIFFER:"; diff "$tmp/py" "$tmp/go" | head -20; rc=1
fi
exit $rc
