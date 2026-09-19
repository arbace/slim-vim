#!/bin/sh
# The three-tier memoize, for one phase.
#
# Usage: tools/memo.sh <unit> <work-dir> <build-dir> [pipeline]
#
# A unit is a phase N, or a stage A-B of the whim pipeline (tools/stages.sh): its
# input is the boundary before A, its result the boundary of B, and nothing in
# between is a boundary.  A single phase is keyed exactly as it always was.
#
# A phase is a function of the tree handed to it, so it can be memoized -- and
# there are three different things worth memoizing, at three different costs:
#
#   TIER 3, the RESULT.  Keyed by the input boundary and the implementation's
#     identity together.  A hit costs a tar extraction and no thought at all.
#     This is what makes re-running a pass free, and what makes editing one
#     phase re-run that phase and the ones after it, rather than all ten.
#
#   TIER 2, the CODE.  pipes/<pipeline><N>.sh, or its -edit.sh and -check.sh
#     parts with the sweep between them (tools/phaserun.sh): a deterministic program.  Fast,
#     checkable, and brittle exactly where upstream is free to move.  Its
#     degenerate form is a patch, which tools/synth.sh can write automatically
#     from what tier 1 did; improving it means replacing patch with algorithm,
#     and the size of what is left is the measure of how well the phase is
#     understood.
#
#   TIER 1, the AGENT.  claude -p, scoped to one phase.  Slow, expensive, and
#     the only tier that can cope with something it has not seen.  It is not a
#     function -- two runs may differ -- so its result is cached but never
#     treated as a check, and its real output is the tier 2 that gets
#     synthesised from it.
#
# The fall-through is the whole construct: result, else code, else agent -- and
# an agent run always leaves a tier 2 behind, so the same input never costs an
# agent twice.
set -eu
set -o pipefail          # the tier-2 run is piped through an indenter

unit=${1:?usage: memo.sh <unit> <work-dir> <build-dir> [pipeline]}
work=${2:?}
build=${3:?}
. tools/pipeline.sh "${4:-slim}"
first=${unit%-*}
phase=${unit#*-}          # the boundary a unit ends at is its last phase's

cache=.cache/$TAG$unit
mkdir -p "$cache"

# The input half of the key, and it must be a FUNCTION of the input.  `input`
# is the pipeline's own immutable input, and it is right for the first unit
# only: a unit that starts at 0 has no boundary before it.  Anything else must
# read the boundary before it and REFUSE when that file is absent -- a missing
# r$((first - 1)) means the phase list has a gap, and falling back to `input`
# there keys the unit on a digest that never moves, so a cached result is served
# back whatever the real input became.  Measured: phase 36's result, cached
# against r30, was a hit after a rebase onto r32, and the pass reported a
# boundary in twelve seconds that was the phase applied to the wrong tree.
# tools/verifypass.sh tests `first = 0` and this used to test `cat` failing,
# which is the same answer to a different question.
if [ "$first" = 0 ]; then
    in_digest=$(cat "$build/input.sha256")
else
    in_prev=$build/$TAG$(($first - 1)).sha256
    [ -f "$in_prev" ] || {
        echo "memo: $PIPE unit $unit wants $TAG$(($first - 1)), which does not exist." >&2
        echo "      Phases must be contiguous; $PIPE's list has a gap before $first." >&2
        exit 1
    }
    in_digest=$(cat "$in_prev")
fi
impl=$(tools/implhash.sh "$unit" "$PIPE")
key=$(printf '%s\n%s\n%s\n' "$unit" "$in_digest" "$impl" | sha256sum | cut -c1-32)

start=$(date +%s)

# A pass is a long-running thing whose only feedback is this log, so say what
# is starting before it starts: which phase, what it is called, and how far
# through the ten we are.  A phase that prints nothing for six minutes looks
# indistinguishable from a hung one otherwise.
if [ "$first" = "$phase" ]; then
    name=$(tools/phasename.sh "$phase" "$PIPE" 2>/dev/null || true)
else
    name="$((phase - first + 1)) phases, one sweep: $(tools/phasename.sh "$first" "$PIPE" 2>/dev/null || true) ... $(tools/phasename.sh "$phase" "$PIPE" 2>/dev/null || true)"
fi
# Bold only for a terminal.  This output is piped as often as it is watched,
# and an escape sequence in a log file is noise rather than emphasis.
if [ -t 1 ]; then b=$(printf '\033[1m'); r=$(printf '\033[0m'); else b=; r=; fi
units=$(tools/stages.sh "$PIPE" 2>/dev/null || true)
n=0; i=0
for _u in $units; do n=$((n + 1)); [ "$_u" = "$unit" ] && i=$n; done
[ "$first" = "$phase" ] && what=phase || what=stage
if [ "$i" = 0 ]; then of="[of $(tools/stages.sh "$PIPE" --of "$phase")]"; else of="[$i/$n]"; fi
printf '\n  %s%s %s %s%s  %s\n' "$b" "$of" "$what" "$unit" "$r" "$name"

# Cumulative elapsed, so the clock is visible without waiting for the summary.
since() {
    [ -f "$build/pass-start" ] || { echo ''; return; }
    t=$(( $(date +%s) - $(cat "$build/pass-start") ))
    printf ' - %dm%02ds into the pass' "$((t / 60))" "$((t % 60))"
}

# --- tier 3: the result ---------------------------------------------------
if [ -f "$cache/$key.tar" ] && [ -f "$cache/$key.sha256" ]; then
    tools/restore.sh "$cache/$key.tar" "$work"
    cp "$cache/$key.sha256" "$build/$TAG$phase.sha256"
    cp "$cache/$key.sha256.files" "$build/$TAG$phase.sha256.files"
    cp "$cache/$key.tar" "$build/$TAG$phase.tar"
    echo cached > "$build/$TAG$phase.kind"
    echo 0 > "$build/$TAG$phase.seconds"
    printf '      %-12s %s  cached for this input%s\n' "tier 3" \
        "$(cut -c1-12 "$cache/$key.sha256")" "$(since)"
    exit 0
fi

# --- tier 2: the code -----------------------------------------------------
tier=
if [ "$(tools/phaserun.sh --parts "$PIPE" "$unit" | grep -c '')" -ge "$((phase - first + 1))" ]; then
    # Keep the input, so that a failure can still be handed to tier 1 from the
    # state the phase was actually given.
    if [ "$first" = 0 ]; then
        cp "$build/input.tar" "$build/.memo-in.tar"
    else
        cp "$build/$TAG$(($first - 1)).tar" "$build/.memo-in.tar"
    fi
    # Indented, so the tools' own reports read as subordinate to the phase
    # lines rather than competing with them.
    # tools/phaserun.sh runs a whole program as it is, and a split one as its
    # edit, the sweep and its check.
    if tools/phaserun.sh "$PIPE" "$unit" "$work" 2>&1 | sed 's/^/      /'; then
        tier=program
    else
        if [ "$first" = "$phase" ]; then
            echo "  tier 2       $TAG$phase FAILED -- falling through to the agent"
        else
            echo "  tier 2       stage $unit FAILED -- running its phases one at a time"
        fi
        tools/restore.sh "$build/.memo-in.tar" "$work"
    fi
    rm -f "$build/.memo-in.tar"
fi

# --- a stage that failed: one phase at a time ----------------------------
# A stage is several phases sharing a sweep, and its failure does not say which
# phase is at fault -- or whether any is: a schedule can fail where each phase on
# its own does not.  So each phase runs as a unit of its own, through this same
# memoize, from the stage's input: each gets its own sweep, its own boundary and
# its own tier 1 if its program fails, exactly as before stages existed.  The
# boundaries written in between are real ones, and the stage's result is the
# last of them.
if [ -z "$tier" ] && [ "$first" != "$phase" ]; then
    for p in $(seq "$first" "$phase"); do
        tools/restore.sh "$build/$TAG$(($p - 1)).tar" "$work" 2>/dev/null \
            || tools/restore.sh "$build/input.tar" "$work"
        tools/memo.sh "$p" "$work" "$build" "$PIPE"
    done
    tier=phases
fi

# --- tier 1: the agent ----------------------------------------------------
if [ -z "$tier" ]; then
    tools/agentphase.sh "$phase" "$work" "$PIPE"
    tier=agent
fi

now=$(date +%s)
echo "$tier" > "$build/$TAG$phase.kind"
echo "$((now - start))" > "$build/$TAG$phase.seconds"
printf '      %-12s %s, %dm%02ds%s\n' \
    "tier $(case $tier in agent) echo 1 ;; phases) echo '1/2' ;; *) echo 2 ;; esac)" "$tier" \
    "$(((now - start) / 60))" "$(((now - start) % 60))" "$(since)"

# --- memoize the result ---------------------------------------------------
tools/snapshot.sh "$work" "$build/$TAG$phase.tar" "$build/$TAG$phase.sha256"
cp "$build/$TAG$phase.tar" "$cache/$key.tar"
cp "$build/$TAG$phase.sha256" "$cache/$key.sha256"
cp "$build/$TAG$phase.sha256.files" "$cache/$key.sha256.files"

# --- and memoize the AGENT'S BEHAVIOUR as code ----------------------------
# This is the part that makes the construct pay.  An agent run that is merely
# cached saves nothing the next time upstream moves; an agent run that leaves a
# program behind turns one expensive answer into a cheap one for ever.
if [ "$tier" = agent ]; then
    tools/synth.sh "$phase" "$build" "$PIPE"
fi
