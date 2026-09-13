#!/bin/sh
# What pure-vim does differently from slim-vim, as a check rather than a report.
#
# Usage: tools/puredelta.sh <binary> <source> [--term-moved] [--cases c1,c2] [commands...]
#
# This is the rule that separates PURE-GOAL.md from SLIM-GOAL.md.  There, any
# behavioural change is a bug and the check is "nothing moved".  Here a change
# is the point, so the check is "exactly this moved" -- the phase says which
# behaviour it is removing, in advance, and the harness proves it removed that
# and nothing else.
#
# "Six commands differ" is a check.  "Some commands differ" is not.
set -eu

bin=${1:?usage: puredelta.sh <binary> <source> [--cases c1,c2] [commands...]}
src=${2:?}
shift 2

# A phase may change an editing BEHAVIOUR as well as an Ex command's exit, and
# until Phase 12 none had, so this tool asserted "behaviour: none" outright.
# That is the right default -- most of what is removed here is a command, not a
# keystroke -- but a default is not a check, and a phase that genuinely moves a
# case has to be able to say which.  Declared the same way and held to the same
# rule: exactly these, and no others.
term_moved=no
if [ "${1:-}" = "--term-moved" ]; then
    term_moved=yes
    shift
fi
cases=
if [ "${1:-}" = "--cases" ]; then
    cases=$(printf '%s' "$2" | tr ',' '\n' | sort -u | tr '\n' ' ')
    shift 2
fi
expected=$(printf '%s\n' "$@" | sort -u | tr '\n' ' ')

base=.reference/baselines
[ -d "$base/behaviour" ] || { echo "  delta        no slim baselines to compare against"; exit 0; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

python3 tools/behaviour.py "$bin" "$tmp/b" >/dev/null
moved=$(diff -rq "$base/behaviour" "$tmp/b" 2>/dev/null | grep '^Files' | sed 's/.*behaviour\///; s/ and .*//' | sort -u | tr '\n' ' ')
if [ "$moved" != "$cases" ]; then
    echo "  delta        behaviour cases that moved:"
    echo "                 got      ${moved:-(none)}"
    echo "                 expected ${cases:-(none)}"
    fail=1
fi

python3 tools/termcheck.py "$bin" "$tmp/m" >/dev/null
# The terminal table is declared the same way the behaviour cases are.  Until
# Phase 22 no phase could move it, so "expected unchanged" was the whole check;
# a phase that makes every TERM resolve to one entry has to be able to say so.
if [ "$term_moved" = yes ]; then
    if diff -q "$base/ref-term.txt" "$tmp/m" >/dev/null; then
        echo "  delta        the terminal table was declared to move and did not"
        fail=1
    fi
else
    if ! diff -q "$base/ref-term.txt" "$tmp/m" >/dev/null; then
        echo "  delta        the terminal table moved, expected unchanged"
        fail=1
    fi
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
if [ -n "$cases" ]; then
    echo "  delta        exactly as declared: $expected; cases: $cases"
else
    echo "  delta        exactly as declared: $expected"
fi
