#!/bin/sh
# What whim-vim does differently from slim-vim, as a check rather than a report.
#
# Usage: tools/whimdelta.sh <binary> <source> --phase N
#        tools/whimdelta.sh <binary> <source> [--term-moved] [--cases c1,c2] [commands...]
#        tools/whimdelta.sh --declared N
#
# --phase N checks the delta pipes/whim.delta declares up to phase N: every line
# for a phase <= N, a command added by its name and taken out by drop:name, a case
# by case:name, the terminal table by term-moved.  tools/phaserun.sh calls it once
# per stage, for the stage's last phase, because the list up to a phase is the
# whole difference from slim at that phase and so contains every earlier phase's.
# The second form states a list by hand.  --declared N prints the commands phase N
# itself declares, one per line -- phase 80's edit reads its table cut from there.
#
# This is the rule that separates WHIM-GOAL.md from SLIM-GOAL.md.  There, any
# behavioural change is a bug and the check is "nothing moved".  Here a change
# is the point, so the check is "exactly this moved" -- the phase says which
# behaviour it is removing, in advance, and the harness proves it removed that
# and nothing else.
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
    awk -v N="$1" -v WHAT="$2" "$delta_awk" pipes/whim.delta
}

if [ "${1:-}" = "--declared" ]; then
    declared "${2:?usage: whimdelta.sh --declared N}" own
    exit 0
fi

bin=${1:?usage: whimdelta.sh <binary> <source> --phase N | [--term-moved] [--cases c1,c2] [commands...]}
src=${2:?}
shift 2

# A phase may change an editing BEHAVIOUR as well as an Ex command's exit, and
# until Phase 8 none had, so this tool asserted "behaviour: none" outright.
# That is the right default -- most of what is removed here is a command, not a
# keystroke -- but a default is not a check, and a phase that genuinely moves a
# case has to be able to say which.  Declared the same way and held to the same
# rule: exactly these, and no others.
if [ "${1:-}" = "--phase" ]; then
    n=${2:?usage: whimdelta.sh <binary> <source> --phase N}
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

# Before anything behavioural: no option global may be left without the row
# that initialises it.  This is a source question rather than a behavioural one,
# but it belongs here because it is the whim pipeline that drops rows, and
# because the thing it catches is invisible to every check that follows -- an
# orphaned global is *used*, so no warning names it, and it segfaults only on
# the one command that reaches it.  See orphanopts.
#
# It runs ALONGSIDE the harnesses rather than before them: it reads the source,
# they run the binary, and neither waits for the other.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
tools/st.sh orphanopts "$src" > "$tmp/orphanopts" 2>&1 &
pid_o=$!

orphans() {
    if wait $pid_o; then cat "$tmp/orphanopts"; else cat "$tmp/orphanopts"; fail=1; fi
}

base=.reference/baselines
if [ ! -d "$base/behaviour" ]; then
    orphans
    echo "  delta        no slim baselines to compare against"
    exit $fail
fi

# THE THREE HARNESSES ARE INDEPENDENT, so they run at once.  Each writes into
# its own directory under $tmp and reads nothing the others write; verify.sh has
# always run its harnesses this way.  Serially they were 4.4 + 1.7 + 2.2
# seconds, which is a third of a phase that does its actual work in two.
#
# They are started here and waited for before the first comparison, rather than
# each being waited for in turn, because the slowest of the three is the first
# one compared.
tools/st.sh behaviour "$bin" "$tmp/b" >/dev/null &
pid_b=$!
tools/st.sh termcheck "$bin" "$tmp/m" >/dev/null &
pid_m=$!
tools/st.sh exsweep "$bin" "$src" "$tmp/s" >/dev/null &
pid_s=$!
wait $pid_b $pid_m $pid_s
orphans

moved=$(diff -rq "$base/behaviour" "$tmp/b" 2>/dev/null | grep '^Files' | sed 's/.*behaviour\///; s/ and .*//' | sort -u | tr '\n' ' ')
if [ "$moved" != "$cases" ]; then
    echo "  delta        behaviour cases that moved:"
    echo "                 got      ${moved:-(none)}"
    echo "                 expected ${cases:-(none)}"
    fail=1
fi

# The terminal table is declared the same way the behaviour cases are.  Until
# Phase 19 no phase could move it, so "expected unchanged" was the whole check;
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
