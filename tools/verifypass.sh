#!/bin/sh
# Check every recorded boundary of a pipeline at once, on as many CPUs as there are.
#
# Usage: tools/verifypass.sh slim [unit...]      (run from the repository root)
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
# THE UNIT IS THE STAGE (tools/stages.sh), which for slim is every phase.  (Stages of
# several phases sharing one sweep were whim's, now in github.com/arbace/go-whim.)
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
    # tools/ and pipes/ are the code that RUNS, and they come from a snapshot the
    # parent took once, never from the live tree.  `sh` reads a script by byte
    # offset as it executes it, so rewriting one IN PLACE while a check is running
    # makes the shell resume at a stale offset in new content -- and every unit
    # used to symlink the one live pipes/, so a single edit could reach 36 running
    # checks at once.  Measured, and the quiet case is the reason this matters:
    # a tear landing mid-token gives `syntax error: unexpected "("` at a line that
    # exists in neither version, but a tear landing at a command boundary in a
    # SHORTER file just ends the script -- 10 truncation points out of 10 exited
    # ZERO, with nothing printed and the remaining assertions never run.  A check
    # that reports success without executing its assertions is the failure this
    # whole construct exists to prevent.  git is not the hazard: it writes by
    # atomic rename, so a running shell keeps its fd on the old inode and reads it
    # to the end (measured, both ways).  In-place writers are -- an editor saving
    # over a file, `sed -i` without a temp, a `cp` onto the original.
    ln -s "$scratch/.src/tools" "$d/tools"
    ln -s "$scratch/.src/pipes" "$d/pipes"
    ln -s "$root/.reference/baselines" "$d/.reference/baselines"
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
        # The status is REPORTED and not merely tested.  A unit killed by a
        # signal, one whose script was torn by a concurrent rewrite, and one
        # whose assertion genuinely failed are three different events, and
        # `if ! ...` renders all three as the same word.  128+N is a signal
        # (137 SIGKILL, 141 SIGPIPE), 2 is a shell syntax error -- which here
        # means the check was rewritten while it ran, since every unit symlinks
        # the one pipes/ directory -- and 1 is usually the check saying no.
        # A log that simply ends with nothing after it is the case this exists
        # for: without the number there is nothing to tell those apart.
        if tools/phaserun.sh "$PIPE" "$u" "$PWORK" > log 2>&1; then
            rc=0
        else
            rc=$?
        fi
        if [ "$rc" != 0 ]; then
            case $rc in
                2)   why=' (rc 2: shell syntax -- a torn read?)' ;;
                13[0-9]|14[0-9]) why=" (rc $rc: killed by signal $((rc - 128)))" ;;
                *)   why=" (rc $rc)" ;;
            esac
            echo "$TAG$u FAILED $(( $(date +%s) - start ))s$why -- $d/log" > "$res"
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

pipe=${1:?usage: verifypass.sh slim [unit...]}
shift
jobs=${JOBS:-$(nproc)}
. tools/pipeline.sh "$pipe"
# The units are the pipeline's stages (tools/stages.sh): for slim, a phase each.
# Named units may be any run whose two ends are recorded.
UNITS=$(tools/stages.sh "$PIPE")
if [ $# -gt 0 ]; then UNITS=$*; fi
scratch=$(mktemp -d "${TMPDIR:-/tmp}/verifypass-$PIPE.XXXXXX")
# One snapshot of the code, taken before any unit starts, that every unit links
# to instead of the live tree -- see the note beside those links above.  4 MB and
# a fraction of a second against a run of minutes, and it makes the whole verify
# a function of the tree as it was when the run began rather than of whatever the
# working tree happens to be while it executes.
mkdir -p "$scratch/.src"
cp -a tools "$scratch/.src/tools"
cp -a pipes "$scratch/.src/pipes"
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
