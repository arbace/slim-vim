#!/bin/sh
# Build the input each whim phase's EDIT is handed, for the cutter comparison.
#
# Usage: phasecorpus.sh <stage>...        e.g. phasecorpus.sh 42-63 13-41
#
# A stage runs its edits in order on text NO SWEEP HAS TOUCHED since the stage
# began, so the input to phase 51 is nine edits into stage 42-63 and exists
# nowhere on disk -- which is why comparing a cutter like keepbytes against the
# recorded boundaries cuts nothing at all and the comparison reports VACUOUS.
#
# This replays a stage's edits the way tools/phaserun.sh does, in a scratch of
# its own, and saves a copy of the tree BEFORE each edit.  It deliberately does
# not sweep and does not run the checks: what is wanted is the text an edit
# sees, not a boundary.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
out=${GOCMP_CORPUS:-.gocorpus}/phases
mkdir -p "$out"

for unit in "$@"; do
    first=${unit%%-*}
    phases=$(awk -v u="$unit" '$1 == "stage" && $2 == u { for (i = 3; i <= NF; i++) print $i }' \
             pipes/whim.stages 2>/dev/null)
    [ -n "$phases" ] || phases=$(echo "$unit" | tr '-' ' ' | awk '{ for (i = $1; i <= $NF; i++) print i }')

    work=$(mktemp -d)
    # A stage starts from the RECORDED BOUNDARY before it.  The "unswept"
    # corpus is not that: unswept/whim42.c has already been through phase
    # 42's own edit, so starting there makes phase 42 refuse with
    # "the :hide modifier -- matched 0 times".
    src=${GOCMP_CORPUS:-.gocorpus}/wz/whim-q$((first - 1)).c
    [ -f "$src" ] || { echo "phasecorpus: no unswept input for stage $unit ($src)"; rm -rf "$work"; continue; }
    cp "$src" "$work/whim-vim.c"

    for p in $phases; do
        [ -f "pipes/whim$p-edit.sh" ] || continue
        cp "$work/whim-vim.c" "$out/whim$p-in.c"
        state=$(mktemp -d)
        grep -c '' "$work/whim-vim.c" > "$state/input-lines"
        if ! sh "pipes/whim$p-edit.sh" "$work" "$state" >/dev/null 2>&1; then
            echo "phasecorpus: whim$p-edit.sh failed; stopping stage $unit at $p"
            rm -rf "$state"
            break
        fi
        rm -rf "$state"
    done
    rm -rf "$work"
    echo "phasecorpus: stage $unit done"
done
ls "$out" | wc -l | sed 's/^/phasecorpus: /;s/$/ per-phase inputs/'
