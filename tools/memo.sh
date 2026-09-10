#!/bin/sh
# The three-tier memoize, for one phase.
#
# Usage: tools/memo.sh <phase> <work-dir> <build-dir>
#
# A phase is a function of the tree handed to it, so it can be memoized -- and
# there are three different things worth memoizing, at three different costs:
#
#   TIER 3, the RESULT.  Keyed by the input boundary and the implementation's
#     identity together.  A hit costs a tar extraction and no thought at all.
#     This is what makes re-running a pass free, and what makes editing one
#     phase re-run that phase and the ones after it, rather than all ten.
#
#   TIER 2, the CODE.  tools/phase<N>.sh: a deterministic program.  Fast,
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

phase=${1:?usage: memo.sh <phase> <work-dir> <build-dir>}
work=${2:?}
build=${3:?}

cache=.cache/p$phase
mkdir -p "$cache"

in_digest=$(cat "$build/p$(($phase - 1)).sha256" 2>/dev/null \
            || cat "$build/input.sha256")
impl=$(tools/implhash.sh "$phase")
key=$(printf '%s\n%s\n%s\n' "$phase" "$in_digest" "$impl" | sha256sum | cut -c1-32)

start=$(date +%s)

# --- tier 3: the result ---------------------------------------------------
if [ -f "$cache/$key.tar" ] && [ -f "$cache/$key.sha256" ]; then
    tools/restore.sh "$cache/$key.tar" "$work"
    cp "$cache/$key.sha256" "$build/p$phase.sha256"
    cp "$cache/$key.sha256.files" "$build/p$phase.sha256.files"
    cp "$cache/$key.tar" "$build/p$phase.tar"
    echo cached > "$build/p$phase.kind"
    echo 0 > "$build/p$phase.seconds"
    printf '  %-12s p%s cached  %s  (impl %s)\n' "tier 3" "$phase" \
        "$(cut -c1-12 "$cache/$key.sha256")" "$impl"
    exit 0
fi

# --- tier 2: the code -----------------------------------------------------
tier=
if [ -x "tools/phase$phase.sh" ]; then
    # Keep the input, so that a failure can still be handed to tier 1 from the
    # state the phase was actually given.
    cp "$build/p$(($phase - 1)).tar" "$build/.memo-in.tar" 2>/dev/null \
        || cp "$build/input.tar" "$build/.memo-in.tar"
    if "tools/phase$phase.sh" "$work"; then
        tier=program
    else
        echo "  tier 2       p$phase FAILED -- falling through to the agent"
        tools/restore.sh "$build/.memo-in.tar" "$work"
    fi
    rm -f "$build/.memo-in.tar"
fi

# --- tier 1: the agent ----------------------------------------------------
if [ -z "$tier" ]; then
    tools/agentphase.sh "$phase" "$work"
    tier=agent
fi

now=$(date +%s)
echo "$tier" > "$build/p$phase.kind"
echo "$((now - start))" > "$build/p$phase.seconds"
printf '  %-12s p%s by %s, %ss\n' "tier $([ "$tier" = agent ] && echo 1 || echo 2)" \
    "$phase" "$tier" "$((now - start))"

# --- memoize the result ---------------------------------------------------
tools/snapshot.sh "$work" "$build/p$phase.tar" "$build/p$phase.sha256"
cp "$build/p$phase.tar" "$cache/$key.tar"
cp "$build/p$phase.sha256" "$cache/$key.sha256"
cp "$build/p$phase.sha256.files" "$cache/$key.sha256.files"

# --- and memoize the AGENT'S BEHAVIOUR as code ----------------------------
# This is the part that makes the construct pay.  An agent run that is merely
# cached saves nothing the next time upstream moves; an agent run that leaves a
# program behind turns one expensive answer into a cheap one for ever.
if [ "$tier" = agent ]; then
    tools/synth.sh "$phase" "$build"
fi
