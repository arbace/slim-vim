#!/bin/sh
# Check every recorded boundary of a pipeline at once, on as many CPUs as there are.
#
# Usage: tools/verifypass.sh slim|whim [unit...]      (run from the repository root)
#        JOBS=n to run fewer at once than there are CPUs
#        KEEP=1 to keep every phase's work and log even when all reproduce
#
# A second pass from an empty cache exists to prove that each phase reproduces
# the boundary it recorded.  It does not have to be a PASS.  Every phase is a pure
# function of the boundary before it, so the same proof is: for every N, run
# phase N on the recorded boundary N-1 and require the recorded boundary N.  By
# induction from the input, that is exactly what a sequential cold pass shows --
# and the phases no longer wait for each other, so it costs the slowest phase
# rather than the sum of them.  Measured on 64 CPUs: the whim pass is 2,489
# seconds of phases in sequence, and this checks all 34 boundaries in about two
# and a half minutes; slim's twelve take 170 seconds, the length of Phase 8.
#
# It found something on its first run, too: `src/xxd/xxd`, upstream's second
# binary, embeds the directory it was built in, so slim's first two boundaries
# depended on where the phase ran.  A pass that always runs in the same place
# could never have shown that.
#
# THE UNIT IS THE STAGE (tools/stages.sh).  For slim that is every phase; for whim it
# is a run of phases sharing one sweep, and only its end is recorded, so each stage
# runs on the recorded end of the stage before it.  Measured with twelve whim
# stages: every boundary in 594 s of wall time, the length of stage 42-63.
#
# THE INDUCTION NEEDS ITS INPUTS TO BE THE RECORDED ONES, so each job first
# digests the tar it was handed and requires the recording for the boundary
# before.  A tar that drifted from its digest would otherwise make the check
# prove something about the wrong tree.
#
# ISOLATION WITHOUT TOUCHING A PHASE PROGRAM.  The programs name every path
# relative to the directory they run in -- .cache/compile, .cache/symbols,
# .reference/baselines -- so each job gets a scratch root of its own: tools/, pipes/
# and the baselines linked in read-only, a .cache/ nobody else writes, and its own
# work tree.  No memo, no tier 3 and no agent: the program is run directly,
# because the question is what the PROGRAM produces.
#
# The program is run through tools/phaserun.sh, exactly as memo.sh runs it, so a
# split phase gets its sweep and its state directory -- including the symbol
# snapshot of its own input, which this script used to write for it.
set -eu

if [ "${1:-}" = "--one" ]; then
    pipe=$2; u=$3; scratch=$4; root=$(pwd)
    . tools/pipeline.sh "$pipe"
    first=${u%-*}; n=${u#*-}
    oracle=.reference/$PIPE-phases
    want_of() {
        if [ -f "$oracle/$TAG$1.sha256" ]; then cat "$oracle/$TAG$1.sha256"
        elif [ -f "$oracle/$TAG$1.sha256.advisory" ]; then cat "$oracle/$TAG$1.sha256.advisory"
        fi
    }
    if [ "$first" = 0 ]; then in_tar=$PBUILD/input.tar; in_want=$(cat "$PBUILD/input.sha256")
    else in_tar=$PBUILD/$TAG$((first - 1)).tar; in_want=$(want_of $((first - 1))); fi
    want=$(want_of "$n")
    d=$scratch/$TAG$u
    res=$scratch/$TAG$u.result
    mkdir -p "$d/.reference" "$d/.cache"
    ln -s "$root/tools" "$d/tools"
    ln -s "$root/pipes" "$d/pipes"
    ln -s "$root/.reference/baselines" "$d/.reference/baselines"
    # The whim pipeline's declared input, which its phase 0 compares the seed
    # against by name.  Read-only, like everything else linked in.
    if [ -f "$root/slim-vim.c" ]; then ln -s "$root/slim-vim.c" "$d/slim-vim.c"; fi
    [ -n "$want" ] || { echo "$TAG$u UNRECORDED" > "$res"; exit 0; }
    start=$(date +%s)
    (
        cd "$d"
        tools/restore.sh "$root/$in_tar" "$PWORK" >/dev/null
        tools/snapshot.sh "$PWORK" in.tar in.sha256 >/dev/null
        if [ "$(cat in.sha256)" != "$in_want" ]; then
            echo "$TAG$u INPUT $(cut -c1-12 in.sha256) is not the recorded $(printf %s "$in_want" | cut -c1-12)" > "$res"
            exit 0
        fi
        rm -f in.tar
        if ! tools/phaserun.sh "$PIPE" "$u" "$PWORK" > log 2>&1; then
            echo "$TAG$u FAILED $(( $(date +%s) - start ))s -- $d/log" > "$res"
            exit 0
        fi
        tools/snapshot.sh "$PWORK" out.tar out.sha256 >/dev/null
        rm -f out.tar
        secs=$(( $(date +%s) - start ))
        if [ "$(cat out.sha256)" = "$want" ]; then
            echo "$TAG$u ok $(cut -c1-12 out.sha256) ${secs}s" > "$res"
        else
            echo "$TAG$u DIFFERS got $(cut -c1-12 out.sha256), recorded $(printf %s "$want" | cut -c1-12) ${secs}s -- $d" > "$res"
        fi
    )
    exit 0
fi

pipe=${1:?usage: verifypass.sh slim|whim [unit...]}
shift
jobs=${JOBS:-$(nproc)}
. tools/pipeline.sh "$pipe"
# The units are the pipeline's stages (tools/stages.sh): a phase for slim, a run of
# phases sharing one sweep for whim, whose recorded boundaries are its stage ends.
# Named units may be any run whose two ends are recorded.
UNITS=$(tools/stages.sh "$PIPE")
if [ $# -gt 0 ]; then UNITS=$*; fi
scratch=$(mktemp -d "${TMPDIR:-/tmp}/verifypass-$PIPE.XXXXXX")
start=$(date +%s)
n=0; for _p in $UNITS; do n=$((n + 1)); done
printf '  %-12s %d units of %s, %d at a time, in %s\n' "verifypass" "$n" "$PIPE" "$jobs" "$scratch"

printf '%s\n' $UNITS | xargs -P "$jobs" -I{} sh tools/verifypass.sh --one "$PIPE" {} "$scratch"

fail=0
for p in $UNITS; do
    r=$(cat "$scratch/$TAG$p.result" 2>/dev/null || echo "$TAG$p NO RESULT")
    case "$r" in
        "$TAG$p ok "*) ;;
        *) fail=1 ;;
    esac
    printf '      %s\n' "$r"
done
wall=$(( $(date +%s) - start ))
sum=$(cat "$scratch"/*.result 2>/dev/null | grep -oE ' [0-9]+s' | tr -dc '0-9\n' | awk '{s+=$1} END {print s+0}')
if [ "$fail" = 0 ]; then
    printf '  %-12s every boundary reproduces: %ds of phases in %ds of wall time\n' "verifypass" "$sum" "$wall"
    if [ -n "${KEEP:-}" ]; then echo "               kept in $scratch"; else rm -rf "$scratch"; fi
else
    printf '  %-12s NOT every boundary reproduces -- the work is kept in %s\n' "verifypass" "$scratch"
    exit 1
fi
