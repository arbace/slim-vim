#!/bin/sh
# What pure-vim does differently from slim-vim, as a check rather than a report.
#
# Usage: tools/puredelta.sh <binary> <source> [expected-commands...]
#
# This is the rule that separates PURE-GOAL.md from SLIM-GOAL.md.  There, any
# behavioural change is a bug and the check is "nothing moved".  Here a change
# is the point, so the check is "exactly this moved" -- the phase says which
# behaviour it is removing, in advance, and the harness proves it removed that
# and nothing else.
#
# "Six commands differ" is a check.  "Some commands differ" is not.
set -eu

bin=${1:?usage: puredelta.sh <binary> <source> [expected-commands...]}
src=${2:?}
shift 2
expected=$(printf '%s\n' "$@" | sort -u | tr '\n' ' ')

base=.reference/baselines
[ -d "$base/behaviour" ] || { echo "  delta        no slim baselines to compare against"; exit 0; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

python3 tools/behaviour.py "$bin" "$tmp/b" >/dev/null
moved=$(diff -rq "$base/behaviour" "$tmp/b" 2>/dev/null | grep '^Files' | sed 's/.*behaviour\///; s/ and .*//' | tr '\n' ' ')
if [ -n "$moved" ]; then
    echo "  delta        behaviour cases moved: $moved"
    echo "               expected none -- these do not touch the runtime"
    fail=1
fi

python3 tools/termcheck.py "$bin" "$tmp/m" >/dev/null
if ! diff -q "$base/ref-term.txt" "$tmp/m" >/dev/null; then
    echo "  delta        the terminal table moved, expected unchanged"
    fail=1
fi

python3 tools/exsweep.py "$bin" "$src" "$tmp/s" >/dev/null
changed=$(diff "$base/ref-exsweep.txt" "$tmp/s" | grep '^[<>]' | awk '{print $2}' | sort -u | tr '\n' ' ')
if [ "$changed" != "$expected" ]; then
    echo "  delta        Ex commands that moved:"
    echo "                 got      $changed"
    echo "                 expected $expected"
    fail=1
fi

if [ "$fail" != 0 ]; then
    echo "               A phase here may change behaviour, but only the behaviour"
    echo "               it said it would.  Anything else is a bug, and a delta"
    echo "               list that is merely widened to fit is not a check."
    exit 1
fi
echo "  delta        exactly as declared: $expected"
