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
# THE DELTA IS THE STAGE'S.  A delta list is the whole difference from slim at its
# phase, so only the last phase's is checked; every earlier check runs with
# WHIMDELTA_SKIP set (tools/whimdelta.sh).
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
for p in $phases; do
    state=.cache/state/$TAG$p
    rm -rf "$state"
    mkdir -p "$state"
    grep -c '' "$f" > "$state/input-lines"
    [ "$first" = "$last" ] || printf '  %-12s %s\n' "edit $p" "$(tools/phasename.sh "$p" "$PIPE" 2>/dev/null || true)"
    "pipes/$IMPL$p-edit.sh" "$work" "$state"
done

tools/sweep.sh "$f"

# The checks, in order, all on the stage's one swept text and one binary.  Every
# check compares symbols with the stage's start.  Only the last phase's check
# checks the delta: a delta list is the whole difference from slim at its phase, so
# the last list is the stage's, and an earlier one would fail on exactly what a
# later phase in the stage removed (tools/whimdelta.sh).
for p in $phases; do
    state=.cache/state/$TAG$p
    rm -rf "$state/symbols"
    cp -r "$stage_state/symbols" "$state/symbols"
    [ "$first" = "$last" ] || printf '  %-12s %s\n' "check $p" "$(tools/phasename.sh "$p" "$PIPE" 2>/dev/null || true)"
    if [ "$p" = "$last" ]; then
        "pipes/$IMPL$p-check.sh" "$work" "$state"
    else
        WHIMDELTA_SKIP=$last "pipes/$IMPL$p-check.sh" "$work" "$state"
    fi
done

for p in $phases; do rm -rf ".cache/state/$TAG$p"; done
rm -rf "$stage_state"
