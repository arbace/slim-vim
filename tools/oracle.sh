#!/bin/sh
# Compare a phase boundary against what the last pass produced there.
#
# Usage: tools/oracle.sh <phase> <build-dir> <oracle-dir>
#
# There are two kinds of recorded boundary and the difference is the whole
# point of this script:
#
#   pN.sha256            a CHECK.  A deterministic run of phase N produced it,
#                        and a pass whose vim.c and behaviour then verified
#                        end to end promoted it.  A mismatch is a failure.
#   pN.sha256.advisory   a REPORT.  An agent produced it.  Agents are not
#                        required to be byte-reproducible in the middle of a
#                        pass -- only the finished vim.c is -- so a mismatch
#                        here is information, not a verdict.
#
# The promotion is deliberate and one-way: a boundary only becomes a hard check
# after something outside it proved the pass still correct.  Recording a
# boundary from the run you are trying to check would make the check agree with
# itself, which is the same mistake as regenerating .reference/ from the
# current binary.
set -eu

phase=${1:?usage: oracle.sh <phase> <build-dir> <oracle-dir> [pipeline]}
build=${2:?}
oracle=${3:?}
. tools/pipeline.sh "${4:-pass}"

got="$build/$TAG$phase.sha256"
[ -f "$got" ] || { echo "  oracle       $TAG$phase: no digest at $got"; exit 1; }

want="$oracle/$TAG$phase.sha256"
advisory="$want.advisory"

short() { cut -c1-12 "$1"; }

if [ -f "$want" ]; then
    if cmp -s "$got" "$want"; then
        printf '  %-12s %s%s matches  %s\n' "oracle" "$TAG" "$phase" "$(short "$got")"
        exit 0
    fi
    printf '  %-12s %s%s DIFFERS  got %s, recorded %s\n' "oracle" "$TAG" "$phase" \
        "$(short "$got")" "$(short "$want")"
    echo "               this boundary is a check, not a report -- explain it."
    if [ -f "$want.files" ]; then
        echo "               first differing files:"
        diff "$want.files" "$got.files" | head -10 | sed 's/^/                 /'
    fi
    exit 1
fi

if [ -f "$advisory" ]; then
    if cmp -s "$got" "$advisory"; then
        printf '  %-12s %s%s matches (advisory)  %s\n' "oracle" "$TAG" "$phase" "$(short "$got")"
    else
        printf '  %-12s %s%s differs (advisory, agent-recorded)  %s vs %s\n' \
            "oracle" "$TAG" "$phase" "$(short "$got")" "$(short "$advisory")"
    fi
    exit 0
fi

printf '  %-12s %s%s unrecorded -- nothing to compare against yet\n' "oracle" "$TAG" "$phase"
exit 0
