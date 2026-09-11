#!/bin/sh
# What the whole harness never executes -- a worklist, not a kill list.
#
# Usage: tools/coverage.sh <source.c> [outfile]
#
# The dead-code sweep finds what is UNUSED: nothing can reach it, and the
# compiler proves it.  This finds something different and much harder --
# code that is reachable, compiles, would run, and never does.  No warning
# will ever name it, so the only way to make the question tractable is to
# measure it: build with --coverage, run every harness there is, and rank what
# was never entered by how big it is.
#
# **This is evidence, not a verdict**, and the distinction matters because the
# list has at least three kinds in it:
#
#   1. genuinely unuseful -- a feature this product's own defaults never reach.
#   2. useful but unexercised -- error paths, rare modes, `vim -` reading
#      stdin.  A hit here is a finding about the HARNESS, not about the code,
#      and arguably the more valuable of the two.
#   3. reachable only through something already removed -- the best candidates,
#      and the reason to re-run this after every phase.
#
# Deleting from this list without deciding which kind each entry is would remove
# working features and call it progress.
set -eu

src=${1:?usage: coverage.sh <source.c> [outfile]}
out=${2:-}
jobs=$(nproc 2>/dev/null || echo 4)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
here=$(pwd)
# Absolute, because every harness below runs with $tmp as its cwd and one of
# them is handed the SOURCE as well as the binary.  A relative path resolved
# fine here and not there, exsweep exited 1, the `&&` chain took the pty
# scenarios with it, and what came back was a coverage figure computed from a
# third of the harness -- lower than the last one, plausible, and wrong.
case $src in
    /*) ;;
    *)  src=$here/$src ;;
esac
cp "$src" "$tmp/cov.c"

( cd "$tmp" && gcc -O0 --coverage -o cov cov.c 2>/dev/null )
echo "  instrument   $(basename "$src") built with --coverage"

# Everything that exercises the editor.  The Ex sweep is the broad one -- 600
# commands -- and the reason this is worth doing at all: a hand-written case
# list would find its own blind spots.
# Each is run and REPORTED separately.  Chaining them with `&&` meant a harness
# that failed silently removed the two after it from the measurement, and the
# only symptom was a number that had moved the wrong way.
ran=
for h in behaviour:b exsweep:s ptycheck:y; do
    name=${h%:*}; dir=${h#*:}
    case $name in
        exsweep) args="./cov $src $tmp/$dir" ;;
        *)       args="./cov $tmp/$dir" ;;
    esac
    if ( cd "$tmp" && python3 "$here/tools/$name.py" $args >/dev/null 2>&1 ); then
        ran="$ran $name"
    else
        echo "  exercise     $name FAILED -- the figure below is short of it"
    fi
done
echo "  exercise    $ran"

( cd "$tmp" && gcov -f -n cov.c 2>/dev/null ) | python3 -c '
import sys, re
lines = sys.stdin.read().split("\n")
never, ran = [], 0
for i, l in enumerate(lines):
    m = re.match(r"Function .(.+).$", l)
    if not m or i + 1 >= len(lines):
        continue
    p = re.match(r"Lines executed:([0-9.]+)% of (\d+)", lines[i + 1])
    if not p:
        continue
    if float(p.group(1)) == 0.0:
        never.append((int(p.group(2)), m.group(1)))
    else:
        ran += 1
never.sort(reverse=True)
total = sum(n for n, _ in never)
print("  functions    %d executed, %d never (%.0f%%)"
      % (ran, len(never), 100.0 * len(never) / (ran + len(never))))
print("  lines        %d in functions never entered" % total)
print()
print("  the largest, which is where to look first:")
for n, f in never[:25]:
    print("    %6d  %s" % (n, f))
' | tee "${out:-/dev/stdout}"
