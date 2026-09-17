#!/bin/sh
# The units a pipeline runs in: its stages, read from the manifest and checked.
#
# Usage: tools/stages.sh <pipeline>              every unit, in order, one per line
#        tools/stages.sh <pipeline> --of <N>     the unit containing phase N
#        tools/stages.sh <pipeline> --check      check the manifest; silent when it holds
#
# A UNIT is what memo.sh keys, the cache stores, make sequences and verifypass.sh
# runs: a phase number (`0`, `79`) or a range of phases (`13-41`), which is a STAGE
# -- every phase's edit in order, one sweep, every phase's check (tools/phaserun.sh).
# Its boundary is the boundary of its last phase: q41 for 13-41.
#
# A pipeline with no pipes/<pipeline>.stages runs every phase as a unit of its own,
# which is slim, and which is exactly how both pipelines ran before stages existed.
#
# THE MANIFEST IS CHECKED, NOT TRUSTED, and this is where the part of it that can be
# checked without running anything is: the stages cover the phase list exactly once
# and in order, a stage of more than one phase is made of split programs, and every
# declared requirement holds of the schedule --
#
#   need P swept          P starts a stage
#   need P silent         P starts a stage
#   need P swept-inner:K  P starts a stage, or K runs just before P in P's stage and
#                         K's edit still runs its inner sweep
#   need P compiles       (a note: nothing in the schedule can show it)
#   apart P K             P and K are in different stages: P's check was measured to
#                         fail once K has run, so it must see a boundary before K
#
# What cannot be checked here is whether a stage lands on the recorded boundary --
# that is tools/oracle.sh at the end of every stage, and it is not optional.
set -eu

. tools/pipeline.sh "${1:?usage: stages.sh <pipeline> [--of N | --check]}"
mode=${2:-}
manifest=pipes/$IMPL.stages

units() {
    if [ ! -f "$manifest" ]; then
        printf '%s\n' $PHASE_LIST
        return
    fi
    awk '$1 == "stage" { print $2 }' "$manifest"
}

check() {
    [ -f "$manifest" ] || return 0
    # Coverage: the ranges, expanded, are the phase list.
    got=$(for u in $(units); do
              a=${u%-*}; b=${u#*-}
              [ "$a" -le "$b" ] || { echo "stages: $u runs backwards" >&2; echo BAD; }
              seq "$a" "$b"
          done | tr '\n' ' ')
    want=$(printf '%s ' $PHASE_LIST)
    if [ "$got" != "$want" ]; then
        echo "stages: $manifest does not cover the $PIPE phases exactly once, in order" >&2
        return 1
    fi
    for u in $(units); do
        case $u in *-*) ;; *) continue ;; esac
        for p in $(seq "${u%-*}" "${u#*-}"); do
            if [ "$(tools/phaserun.sh --parts "$PIPE" "$p" | wc -l)" != 2 ]; then
                echo "stages: phase $p is in stage $u but is not an edit and a check" >&2
                return 1
            fi
        done
    done
    # Requirements.
    awk '$1 == "stage" { print "stage", $2 } $1 == "need" || $1 == "apart" { print $1, $2, $3 }' "$manifest" \
    | awk -v impl="$IMPL" '
        $1 == "stage" { split($2, r, "-"); a = r[1]; b = (2 in r) ? r[2] : r[1]
                        for (p = a; p <= b; p++) { first[p] = (p == a); unit[p] = $2 }
                        next }
        { req[++n] = $0 }
        END {
            bad = 0
            for (i = 1; i <= n; i++) {
                split(req[i], f, " ")
                if (f[1] == "apart") {
                    if (unit[f[2]] == unit[f[3]]) {
                        printf "stages: %s and %s must be apart, and share stage %s\n", f[2], f[3], unit[f[2]] > "/dev/stderr"; bad = 1 }
                    continue
                }
                p = f[2]; what = f[3]
                if (what == "swept" || what == "silent") {
                    if (!first[p]) { printf "stages: %s needs %s input and does not start a stage (%s)\n", p, what, unit[p] > "/dev/stderr"; bad = 1 }
                } else if (what ~ /^swept-inner:/) {
                    k = substr(what, 13)
                    if (!first[p] && (k != p - 1 || unit[k] != unit[p])) {
                        printf "stages: %s needs %s run just before it, in its stage\n", p, k > "/dev/stderr"; bad = 1 }
                    else if (!first[p]) print k
                }
            }
            exit bad
        }' > "${TMPDIR:-/tmp}/stages.$$" || { rm -f "${TMPDIR:-/tmp}/stages.$$"; return 1; }
    for k in $(cat "${TMPDIR:-/tmp}/stages.$$"); do
        if ! grep -q 'tools/sweep\.sh' "pipes/$IMPL$k-edit.sh"; then
            echo "stages: a later phase needs $k's inner sweep, and pipes/$IMPL$k-edit.sh no longer runs one" >&2
            rm -f "${TMPDIR:-/tmp}/stages.$$"
            return 1
        fi
    done
    rm -f "${TMPDIR:-/tmp}/stages.$$"
}

case $mode in
    '')      check && units ;;
    --check) check ;;
    --of)
        n=${3:?usage: stages.sh <pipeline> --of N}
        for u in $(units); do
            if [ "$n" -ge "${u%-*}" ] && [ "$n" -le "${u#*-}" ]; then echo "$u"; exit 0; fi
        done
        echo "stages: no $PIPE unit contains phase $n" >&2
        exit 1 ;;
    *) echo "usage: stages.sh <pipeline> [--of N | --check]" >&2; exit 2 ;;
esac
