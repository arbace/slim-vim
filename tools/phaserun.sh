#!/bin/sh
# Run a unit of a pipeline's tier-2 program: a whole phase, or a STAGE.
#
# Usage: tools/phaserun.sh <pipeline> <unit> <work-dir>   (run from the root)
#        tools/phaserun.sh --parts <pipeline> <unit>
#
# A unit is a phase N or a stage A-B (tools/stages.sh).  The second form prints the
# program files of every phase in it, one per line, and nothing for a phase that
# has none -- which is how memo.sh, implhash.sh, specpass.sh and residue.sh ask
# "is this a program?" without each knowing the shapes.
#
# A phase program has one of two shapes:
#
#   pipes/<pipeline><N>.sh                     WHOLE: run with the work dir, as a
#                                              unit of its own.  Every slim phase,
#                                              whim phase 0, anything synth.sh writes.
#   pipes/<pipeline><N>-edit.sh                SPLIT: the cut, and
#   pipes/<pipeline><N>-check.sh               the proof.  The sweep between is HERE.
#
# A STAGE is a run of split phases: every edit in order, on text no sweep has
# touched since the stage began; ONE tools/sweep.sh; every check in order, on the
# one swept text and its one binary.  A single split phase is a stage of one.
#
# WHY.  70-90% of a whim phase was its final sweep, a fixed cost paid in full by a
# phase that deletes one line (WHIM-PLAN.md, section 1).  Eighty-two sweeps became
# twelve.  Which phases may share a sweep is pipes/<pipeline>.stages, which says
# what each edit needs of its input and which checks need a boundary before a later
# phase; tools/stages.sh --check refuses a schedule that breaks it, and runs here.
#
# THE CONTRACT, which is what makes a check runnable after other phases' edits and a
# shared sweep: the check part reads NOTHING from the edit part's shell.  No
# variable, no function, no trap, no background job.  What passes between them is
# files, in a state directory this driver makes fresh for each phase and hands to
# both parts as their second argument:
#
#   $state/input-lines   written HERE: the line count of the text THIS phase's edit
#                        is handed (unswept, inside a stage).  The check's "N -> M".
#   $state/symbols/      written HERE, once per stage, by tools/symbols.sh from the
#                        text the stage's FIRST edit is handed: the symbol snapshot
#                        tools/phasecheck.sh compares with (and removes).  Inside a
#                        stage every check compares with the stage's start, so "this
#                        phase must lower the count" means the stage must.
#   anything else        written by the EDIT part, named in it, and read by its own
#                        check: phase 80's `words` and `old`, 81's `old`, 82's
#                        `total`, `keep` and `old/whim-vim.c`.  An edit that starts
#                        a background job waits for it before it exits.
#
# THE DELTA IS THE STAGE'S, and no check part states one.  pipes/<pipeline>.delta
# declares what each phase changes; the lines up to a phase are the whole difference
# from the pipeline's baselines at that phase, so the stage's last phase's contains
# every earlier one's, and this driver runs the pipeline's checker (PDELTA) with
# --phase <last> once, after the checks.
#
# The state directories are .cache/state/<tag><N>, and the stage's own
# .cache/state/<tag><unit>.stage, relative to where the unit runs -- never inside
# the work tree, whose every file is part of the boundary digest.  They are removed
# when every check passes and kept when anything fails.
set -eu

if [ "${1:-}" = "--parts" ]; then
    . tools/pipeline.sh "${2:?usage: phaserun.sh --parts <pipeline> <unit>}"
    u=${3:?usage: phaserun.sh --parts <pipeline> <unit>}
    for phase in $(seq "${u%-*}" "${u#*-}"); do
        if [ -f "pipes/$IMPL$phase-edit.sh" ] && [ -f "pipes/$IMPL$phase-check.sh" ]; then
            echo "pipes/$IMPL$phase-edit.sh"
            echo "pipes/$IMPL$phase-check.sh"
        elif [ -f "pipes/$IMPL$phase.sh" ]; then
            echo "pipes/$IMPL$phase.sh"
        fi
    done
    exit 0
fi

. tools/pipeline.sh "${1:?usage: phaserun.sh <pipeline> <unit> <work-dir>}"
unit=${2:?usage: phaserun.sh <pipeline> <unit> <work-dir>}
work=${3:?usage: phaserun.sh <pipeline> <unit> <work-dir>}
first=${unit%-*}
last=${unit#*-}

# A whole program is a unit of its own and runs as it always did.
if [ "$first" = "$last" ] && [ -f "pipes/$IMPL$first.sh" ] \
        && ! { [ -f "pipes/$IMPL$first-edit.sh" ] && [ -f "pipes/$IMPL$first-check.sh" ]; }; then
    exec "pipes/$IMPL$first.sh" "$work"
fi

phases=$(seq "$first" "$last")
for p in $phases; do
    if [ ! -f "pipes/$IMPL$p-edit.sh" ] || [ ! -f "pipes/$IMPL$p-check.sh" ]; then
        echo "  phaserun     $PIPE phase $p has no edit and check to run in stage $unit" >&2
        exit 2
    fi
done
if [ -z "$PSOURCE" ]; then
    echo "  phaserun     the $PIPE pipeline names no single source a sweep can run on" >&2
    exit 2
fi
tools/stages.sh "$PIPE" --check
f=$work/$PSOURCE

# The stage's start: the symbol snapshot, once, of the text the first edit is
# handed -- the one text in a stage that is certain to compile.
stage_state=.cache/state/$TAG$unit.stage
rm -rf "$stage_state"
mkdir -p "$stage_state"
tools/symbols.sh "$f" "$stage_state/symbols"

# The edits, in order, on text no sweep has touched since the stage began.  Each
# phase's state directory is made fresh, gets the line count of the text ITS edit
# is handed, and keeps whatever that edit leaves for its check.
#
# EACH EDIT'S RESULT IS CACHED, keyed like any boundary: the phase, the digest of
# the tree its edit is handed, and the implementation digest of the edit part alone
# (tools/implhash.sh --edit).  Its value is the tree the edit leaves and its state
# directory.  So editing phase K's program re-runs K's edit, and after it only the
# edits whose input really moved -- then the one sweep and the checks, which always
# run -- instead of every edit in the stage.  It is the same construct as tier 3,
# one level down, and it is as safe: a cached edit answers exactly one input and
# one implementation.  A scratch root with a .cache of its own (verifypass.sh)
# recomputes every edit.
tree_digest() {
    ( cd "$work" && find . -type f -print0 | sort -z | xargs -0 sha256sum ) \
        | grep -Ev '/objects/|\.(o|d)$|/(whim-|zero-)?vim$' | sha256sum | cut -c1-32
}
for p in $phases; do
    state=.cache/state/$TAG$p
    rm -rf "$state"
    mkdir -p "$state"
    grep -c '' "$f" > "$state/input-lines"
    name=$(tools/phasename.sh "$p" "$PIPE" 2>/dev/null || true)
    ekey=$(printf '%s\n%s\n%s\n' "$p" "$(tree_digest)" "$(tools/implhash.sh --edit "$p" "$PIPE")" \
           | sha256sum | cut -c1-32)
    ecache=.cache/edit/$TAG$p/$ekey
    if [ -f "$ecache.tree.tar" ] && [ -f "$ecache.state.tar" ]; then
        tools/restore.sh "$ecache.tree.tar" "$work"
        tar --extract --file "$ecache.state.tar" -C "$state"
        printf '  %-12s %s  (edit cached for this input)\n' "edit $p" "$name"
        continue
    fi
    [ "$first" = "$last" ] || printf '  %-12s %s\n' "edit $p" "$name"
    "pipes/$IMPL$p-edit.sh" "$work" "$state"
    mkdir -p ".cache/edit/$TAG$p"
    tar --create --file "$ecache.state.part" -C "$state" --exclude=./input-lines .
    tar --create --file "$ecache.tree.part" -C "$work" .
    mv "$ecache.state.part" "$ecache.state.tar"
    mv "$ecache.tree.part" "$ecache.tree.tar"
done

tools/sweep.sh "$f"

# The checks, in order, all on the stage's one swept text and one binary.  Every
# check compares symbols with the stage's start.
for p in $phases; do
    state=.cache/state/$TAG$p
    rm -rf "$state/symbols"
    cp -r "$stage_state/symbols" "$state/symbols"
    [ "$first" = "$last" ] || printf '  %-12s %s\n' "check $p" "$(tools/phasename.sh "$p" "$PIPE" 2>/dev/null || true)"
    "pipes/$IMPL$p-check.sh" "$work" "$state"
done

# The declared delta, once: pipes/<pipeline>.delta up to the stage's last phase is
# the whole difference from the pipeline's baselines there, and so holds every
# earlier phase's.  The checker is the pipeline's (PDELTA in tools/pipeline.sh):
# tools/whimdelta.sh against slim-vim's baselines, zero's own against whim-vim's.
# Never name a zero tool's path in this file: every whim edit's key reads what
# this file names, so the name would put that tool in all of them.
if [ -f "pipes/$IMPL.delta" ]; then
    "$PDELTA" "$work/${PSOURCE%.c}" "$f" --phase "$last"
fi

for p in $phases; do rm -rf ".cache/state/$TAG$p"; done
rm -rf "$stage_state"
