#!/bin/sh
# What zero-vim does differently from whim-vim, as a check rather than a report.
#
# Usage: tools/zerodelta.sh <binary> <source> --phase N
#        tools/zerodelta.sh <binary> <source> [--term-moved] [--cases c1,c2] [commands...]
#        tools/zerodelta.sh --declared N
#
# tools/whimdelta.sh's rule and grammar, against different baselines.  --phase N
# checks the delta pipes/zero.delta declares up to phase N: a command by its name
# and drop:name, a case by case:name, the terminal table by term-moved.  The second
# form states a list by hand; --declared N prints the commands phase N itself
# declares.
#
# THE BASELINES ARE WHIM-VIM'S: .reference/zero-baselines, recorded by zero phase 0
# from the committed whim-vim.c built with whim's own compile line.  So the delta is
# the difference from whim, not from slim, and it starts empty.  Recording them from
# the pipeline's INPUT is not the mistake CLAUDE.md warns about -- regenerating a
# pipeline's baselines from its own current binary, which agrees by construction.
# whim-vim.c is immutable to this pipeline; zero-vim is what gets compared.
#
# A separate tool and not a mode of whimdelta.sh, because whimdelta.sh is hashed into
# every whim stage's key: a zero line there would re-run all of whim.  This file is
# named by nothing whim runs.
#
# "Six commands differ" is a check.  "Some commands differ" is not.
set -eu

delta_awk='
    /^[ \t]*#/ || NF == 0 { next }
    {
        i = 1
        if ($0 ~ /^[0-9]/) { phase = $1 + 0; i = 2 }
        if (phase > N) next
        for (; i <= NF; i++) {
            w = $i
            if (phase == N && w !~ /^(case:|drop:|term-moved$)/) own[++nown] = w
            if (w == "term-moved") term = 1
            else if (w ~ /^drop:case:/) delete cases[substr(w, 11)]
            else if (w ~ /^drop:/) delete cmds[substr(w, 6)]
            else if (w ~ /^case:/) cases[substr(w, 6)] = 1
            else cmds[w] = 1
        }
    }
    END {
        if (WHAT == "term") print (term ? "yes" : "no")
        else if (WHAT == "cases") for (c in cases) print c
        else if (WHAT == "cmds") for (c in cmds) print c
        else if (WHAT == "own") for (k = 1; k <= nown; k++) print own[k]
    }'
declared() {
    awk -v N="$1" -v WHAT="$2" "$delta_awk" pipes/zero.delta
}

if [ "${1:-}" = "--declared" ]; then
    declared "${2:?usage: zerodelta.sh --declared N}" own
    exit 0
fi

bin=${1:?usage: zerodelta.sh <binary> <source> --phase N | [--term-moved] [--cases c1,c2] [commands...]}
src=${2:?}
shift 2

if [ "${1:-}" = "--phase" ]; then
    n=${2:?usage: zerodelta.sh <binary> <source> --phase N}
    term_moved=$(declared "$n" term)
    cases=$(declared "$n" cases | sort -u | tr '\n' ' ')
    expected=$(declared "$n" cmds | sort -u | tr '\n' ' ')
else
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
fi

# The same source check whimdelta.sh runs beside its harnesses: no option global
# left without the row that initialises it (tools/orphanopts.py).
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
python3 tools/orphanopts.py "$src" > "$tmp/orphanopts" 2>&1 &
pid_o=$!

orphans() {
    if wait $pid_o; then cat "$tmp/orphanopts"; else cat "$tmp/orphanopts"; fail=1; fi
}

# Unlike whimdelta.sh, an absent baseline is a failure and not a note: zero phase 0
# records them before anything is compared, so a missing set means the pipeline
# is being run out of order.
base=.reference/zero-baselines
if [ ! -d "$base/behaviour" ] || [ ! -f "$base/ref-exsweep.txt" ] || [ ! -f "$base/ref-term.txt" ]; then
    orphans
    echo "  delta        no zero baselines at $base -- zero phase 0 records them"
    exit 1
fi

python3 tools/behaviour.py "$bin" "$tmp/b" >/dev/null &
pid_b=$!
python3 tools/termcheck.py "$bin" "$tmp/m" >/dev/null &
pid_m=$!
python3 tools/exsweep.py "$bin" "$src" "$tmp/s" >/dev/null &
pid_s=$!
wait $pid_b $pid_m $pid_s
orphans

moved=$(diff -rq "$base/behaviour" "$tmp/b" 2>/dev/null | grep -E '^(Files|Only in)' | sed 's/^Only in [^:]*: //; s/.*behaviour\///; s/ and .*//' | sort -u | tr '\n' ' ')
if [ "$moved" != "$cases" ]; then
    echo "  delta        behaviour cases that moved:"
    echo "                 got      ${moved:-(none)}"
    echo "                 expected ${cases:-(none)}"
    fail=1
fi

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
if [ -z "$expected$cases" ] && [ "$term_moved" != yes ]; then
    echo "  delta        none, as declared: behaviour, terminal table and every Ex command match whim-vim"
elif [ -n "$cases" ]; then
    echo "  delta        exactly as declared: $expected; cases: $cases"
else
    echo "  delta        exactly as declared: $expected"
fi
