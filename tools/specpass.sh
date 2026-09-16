#!/bin/sh
# Speculate every phase of a pass at once, so the sequential pass only waits
# where it has to.
#
# Usage: tools/specpass.sh slim|whim         (run from the repository root)
#        JOBS=n to run fewer at once than there are CPUs
#        KEEP=1 to keep every job's work and log
#
# A pass is sequential because phase N is a function of boundary N-1.  But a
# repass usually has the previous pass's boundaries lying in the build
# directory, and when a change is to a TOOL rather than to what a phase does --
# a harness, a check, a comment -- every implementation digest moves while
# every boundary stays exactly what it was.  The sequential pass then recomputes
# forty phases to arrive where it started.
#
# So guess that the inputs have not changed.  Each phase runs at once on the
# previous pass's boundary before it, in a scratch root of its own (the
# isolation tools/verifypass.sh uses), and its result goes into the tier 3
# cache under EXACTLY the key tools/memo.sh will look up: the phase, the input
# digest, the implementation digest.  Then the ordinary sequential pass runs.
# Wherever the guess was right, its input digest is the one speculated on and
# the lookup is a hit; from the first phase whose input really changed, the key
# is different, nothing is found, and the phase runs as it always did.
#
# NOTHING HERE IS A CHECK AND NOTHING CAN BE WRONG.  A cached result answers
# only the input and implementation it was keyed by, so a wrong guess costs CPU
# and never correctness.  There is no separate "did the boundary change" step:
# the cache lookup is that step.  A phase that fails here is reported and left
# for the sequential pass, which decides.  An agent phase is not a function and
# is never speculated on.
#
# THE WIN IS THE SHAPE OF THE CHANGE.  A tool-only change: the whole pass in
# the wall time of its slowest phase.  A change to phase K's output: phases
# before K are free, the rest run in sequence as before, and the speculative
# work for K onwards was CPU spent for nothing.  If a recomputed boundary comes
# out equal to the old one again, the phases after it are hits again.
set -eu

if [ "${1:-}" = "--one" ]; then
    pipe=$2; n=$3; scratch=$4; root=$(pwd)
    . tools/pipeline.sh "$pipe"
    res=$scratch/$TAG$n.result
    if [ "$n" = 0 ]; then in_tar=$PBUILD/input.tar; in_sha=$PBUILD/input.sha256
    else in_tar=$PBUILD/$TAG$((n - 1)).tar; in_sha=$PBUILD/$TAG$((n - 1)).sha256; fi
    if [ ! -f "$in_tar" ] || [ ! -f "$in_sha" ]; then
        echo "$TAG$n no-input" > "$res"; exit 0
    fi
    in_digest=$(cat "$in_sha")
    impl=$(tools/implhash.sh "$n" "$PIPE")
    if [ "$impl" = agent ]; then
        echo "$TAG$n agent" > "$res"; exit 0
    fi
    # The same three lines, in the same order, as tools/memo.sh.
    key=$(printf '%s\n%s\n%s\n' "$n" "$in_digest" "$impl" | sha256sum | cut -c1-32)
    cache=$root/.cache/$TAG$n
    if [ -f "$cache/$key.tar" ] && [ -f "$cache/$key.sha256" ]; then
        echo "$TAG$n cached" > "$res"; exit 0
    fi
    d=$scratch/$TAG$n
    mkdir -p "$d/.reference" "$d/.cache"
    ln -s "$root/tools" "$d/tools"
    ln -s "$root/pipes" "$d/pipes"
    ln -s "$root/.reference/baselines" "$d/.reference/baselines"
    if [ -f "$root/slim-vim.c" ]; then ln -s "$root/slim-vim.c" "$d/slim-vim.c"; fi
    start=$(date +%s)
    (
        cd "$d"
        tools/restore.sh "$root/$in_tar" "$PWORK" >/dev/null
        tools/snapshot.sh "$PWORK" in.tar in.sha256 >/dev/null
        if [ "$(cat in.sha256)" != "$in_digest" ]; then
            echo "$TAG$n input-drift $(cut -c1-12 in.sha256) is not $(printf %s "$in_digest" | cut -c1-12)" > "$res"
            exit 0
        fi
        rm -f in.tar
        if [ -f "$PWORK/whim-vim.c" ]; then
            tools/symbols.sh "$PWORK/whim-vim.c" .cache/symbols/before
        fi
        if ! "pipes/$IMPL$n.sh" "$PWORK" > log 2>&1; then
            echo "$TAG$n failed $(( $(date +%s) - start ))s -- $d/log" > "$res"
            exit 0
        fi
        tools/snapshot.sh "$PWORK" out.tar out.sha256 >/dev/null
        mkdir -p "$cache"
        # The tar and its file list first, the digest last and by rename: memo.sh
        # takes a key as present only when the .tar and the .sha256 both exist, so
        # a half-written entry is never mistaken for a result.
        cp out.tar "$cache/$key.tar.part" && mv "$cache/$key.tar.part" "$cache/$key.tar"
        cp out.sha256.files "$cache/$key.sha256.files.part" && mv "$cache/$key.sha256.files.part" "$cache/$key.sha256.files"
        cp out.sha256 "$cache/$key.sha256.part" && mv "$cache/$key.sha256.part" "$cache/$key.sha256"
        echo "$TAG$n ran $(cut -c1-12 out.sha256) $(( $(date +%s) - start ))s" > "$res"
    )
    [ -n "${KEEP:-}" ] || case "$(cat "$res")" in *" ran "*) rm -rf "$d" ;; esac
    exit 0
fi

pipe=${1:?usage: specpass.sh slim|whim}
jobs=${JOBS:-$(nproc)}
. tools/pipeline.sh "$pipe"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/specpass-$PIPE.XXXXXX")
start=$(date +%s)
n=0; for _p in $PHASE_LIST; do n=$((n + 1)); done
printf '  %-12s %d phases of %s speculated on the last pass'"'"'s boundaries, %d at a time\n' \
    "specpass" "$n" "$PIPE" "$jobs"

printf '%s\n' $PHASE_LIST | xargs -P "$jobs" -I{} sh tools/specpass.sh --one "$PIPE" {} "$scratch"

ran=0; cached=0; other=0
for p in $PHASE_LIST; do
    r=$(cat "$scratch/$TAG$p.result" 2>/dev/null || echo "$TAG$p no-result")
    case "$r" in
        *" ran "*) ran=$((ran + 1)) ;;
        *" cached") cached=$((cached + 1)) ;;
        *) other=$((other + 1)); printf '      %s\n' "$r" ;;
    esac
done
wall=$(( $(date +%s) - start ))
sum=$(cat "$scratch"/*.result 2>/dev/null | grep -oE ' [0-9]+s' | tr -dc '0-9\n' | awk '{s+=$1} END {print s+0}')
printf '  %-12s %d ran (%ds of phases in %ds), %d already cached, %d left to the pass\n' \
    "specpass" "$ran" "$sum" "$wall" "$cached" "$other"
if [ "$other" = 0 ] && [ -z "${KEEP:-}" ]; then rm -rf "$scratch"; else echo "               work in $scratch"; fi
