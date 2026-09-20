#!/bin/sh
# Can this phase's check FAIL?
#
# Usage: tools/canfail.sh <pipeline> <phase>...      (from the repository root)
#
# CLAUDE.md asks every phase for evidence that its check can fail -- "a test suite
# that cannot fail is not evidence", and each phase answers with a control of its
# own choosing.  Nothing checks the answers, and nothing asks the question of a
# phase that never thought to ask it of itself.  This does, mechanically, with one
# mutation that applies to every phase in all three pipelines and needs no
# cooperation from the check:
#
#     RUN THE CHECK AGAINST THE PHASE'S OWN INPUT.
#
# A check is handed a work tree and a state directory its edit wrote.  Give it the
# state from a real run and a work tree where THE EDIT NEVER HAPPENED, and it must
# refuse: everything the phase claims to have done is absent.  A check that passes
# there does not distinguish its phase's output from its input, which means the
# phase's whole evidence is that something else did not break.
#
# WHY THIS MUTATION AND NOT A RANDOM ONE.  A corrupted line might be something the
# phase legitimately says nothing about, so a pass would prove nothing and a
# failure might be luck.  The input is the one tree every check has an opinion
# about by construction -- it is the thing the phase was written to change.
#
# WHAT A PASS HERE DOES NOT MEAN.  Refusing on its own input is the weakest
# property worth having, not a good check: it says the check notices the phase
# happened, not that it noticed what the phase MEANT.  Read it as a floor.
#
# It is deliberately not wired into any pass.  It costs three phase runs where a
# pass costs one, it is an audit rather than a gate, and being named by no phase
# program it is in no implementation digest -- so it can be changed freely and
# changes nothing.
set -eu

pipe=${1:?usage: canfail.sh <pipeline> <phase>...}
shift
. tools/pipeline.sh "$pipe"

[ $# -gt 0 ] || { echo "canfail: name at least one phase" >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
for phase in "$@"; do
    edit="pipes/$IMPL$phase-edit.sh"
    check="pipes/$IMPL$phase-check.sh"
    if [ ! -f "$edit" ] || [ ! -f "$check" ]; then
        printf '  %-12s %s\n' "$TAG$phase" "not a split phase -- it has no check to audit, skipped"
        continue
    fi
    prev=$((phase - 1))
    in_tar=$PBUILD/$TAG$prev.tar
    [ "$phase" = 0 ] && in_tar=$PBUILD/input.tar
    if [ ! -f "$in_tar" ]; then
        printf '  %-12s %s\n' "$TAG$phase" "no $in_tar -- run a pass first, skipped"
        continue
    fi

    work=$tmp/work
    state=.cache/state/$TAG$phase

    # --- the real run, which also writes the state the check reads ------------
    rm -rf "$work"; mkdir -p "$work"
    tools/restore.sh "$in_tar" "$work" >/dev/null
    rm -rf "$state"; mkdir -p "$state"
    grep -c '' "$work/$PSOURCE" > "$state/input-lines"
    tools/symbols.sh "$work/$PSOURCE" "$state/symbols" >/dev/null 2>&1 || true
    "$edit" "$work" "$state" >/dev/null 2>&1 || {
        printf '  %-12s %s\n' "$TAG$phase" "the EDIT refused on its own input -- cannot audit, skipped"
        continue
    }
    tools/sweep.sh "$work/$PSOURCE" >/dev/null 2>&1 || true

    # The state as the edit left it, and the swept output the check should pass on.
    rm -rf "$tmp/state"; cp -r "$state" "$tmp/state"
    rm -rf "$tmp/out";   cp -r "$work"  "$tmp/out"

    # --- 1. the control: it must PASS on what the phase really produced -------
    if ! "$check" "$work" "$state" >"$tmp/pass.log" 2>&1; then
        printf '  %-12s %s\n' "$TAG$phase" "INCONCLUSIVE -- the check refused its own real output; see $tmp/pass.log"
        fail=$((fail + 1))
        continue
    fi

    # --- 2. the mutation: the same state, a tree where the edit never ran -----
    rm -rf "$work"; mkdir -p "$work"
    tools/restore.sh "$in_tar" "$work" >/dev/null
    rm -rf "$state"; cp -r "$tmp/state" "$state"
    if "$check" "$work" "$state" >"$tmp/mutant.log" 2>&1; then
        printf '  %-12s %s\n' "$TAG$phase" \
            "CANNOT FAIL -- it passes on its own INPUT, so it does not distinguish this phase"
        fail=$((fail + 1))
    else
        printf '  %-12s %s\n' "$TAG$phase" \
            "can fail -- refuses its own input: $(tail -3 "$tmp/mutant.log" | grep -v '^ *$' | tail -1 | sed 's/^ *//' | cut -c1-66)"
    fi
done

[ "$fail" = 0 ] || exit 1
