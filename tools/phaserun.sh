#!/bin/sh
# Run one phase's tier-2 program: whole, or as an edit, a sweep and a check.
#
# Usage: tools/phaserun.sh <pipeline> <phase> <work-dir>   (run from the root)
#        tools/phaserun.sh --parts <pipeline> <phase>
#
# The second form prints the program files of a phase, one per line, and nothing
# when the phase has none -- which is how memo.sh, implhash.sh, specpass.sh and
# residue.sh ask "is this phase a program?" without each knowing the two shapes.
#
# A phase program has one of two shapes:
#
#   pipes/<pipeline><N>.sh                     WHOLE: run with the work dir.  Every
#                                              slim phase, whim phase 0, and anything
#                                              tools/synth.sh writes.
#   pipes/<pipeline><N>-edit.sh                SPLIT: the edit, then the sweep, run
#   pipes/<pipeline><N>-check.sh               HERE, then the check.
#
# WHY SPLIT.  70-90% of a whim phase is its final tools/sweep.sh, a fixed cost
# paid in full by a phase that deletes one line (WHIM-PLAN.md, section 1).  With the
# sweep owned by the driver rather than written into the program, a later driver
# can run several phases' edits, ONE sweep, and then their checks -- a stage.  This
# one still runs one phase per stage, so every boundary is what it was.
#
# THE CONTRACT, which is what makes a check runnable after other phases' edits and a
# shared sweep: the check part reads NOTHING from the edit part's shell.  No
# variable, no function, no trap, no background job.  What passes between them is
# files, in a state directory this driver makes fresh for the phase and hands to
# both parts as their second argument:
#
#   $state/input-lines   written HERE: the line count of the text the edit is
#                        handed.  The check's report of "N -> M lines".
#   $state/symbols/      written HERE, by tools/symbols.sh, from the same text: the
#                        symbol snapshot tools/phasecheck.sh compares the result
#                        with (and removes).  It used to be the first line of
#                        almost every program; it is the stage's start now.
#   anything else        written by the EDIT part, named in it, and read by its own
#                        check: phase 80's `words` and `old`, 81's `old`, 82's
#                        `includes`, `keep` and `old/whim-vim.c`.  An edit that
#                        starts a background job waits for it before it exits.
#
# The state directory is .cache/state/<tag><N>, relative to where the phase runs --
# never inside the work tree, whose every file is part of the boundary digest.  It
# is removed when the check passes and kept when anything fails.
#
# pipes/<pipeline>.stages is the stage manifest, and says what each phase needs of
# the text its edit is handed.  Nothing reads it yet.
set -eu

if [ "${1:-}" = "--parts" ]; then
    . tools/pipeline.sh "${2:?usage: phaserun.sh --parts <pipeline> <phase>}"
    phase=${3:?usage: phaserun.sh --parts <pipeline> <phase>}
    if [ -f "pipes/$IMPL$phase-edit.sh" ] && [ -f "pipes/$IMPL$phase-check.sh" ]; then
        echo "pipes/$IMPL$phase-edit.sh"
        echo "pipes/$IMPL$phase-check.sh"
    elif [ -f "pipes/$IMPL$phase.sh" ]; then
        echo "pipes/$IMPL$phase.sh"
    fi
    exit 0
fi

. tools/pipeline.sh "${1:?usage: phaserun.sh <pipeline> <phase> <work-dir>}"
phase=${2:?usage: phaserun.sh <pipeline> <phase> <work-dir>}
work=${3:?usage: phaserun.sh <pipeline> <phase> <work-dir>}

edit=pipes/$IMPL$phase-edit.sh
check=pipes/$IMPL$phase-check.sh

if [ ! -f "$edit" ] || [ ! -f "$check" ]; then
    if [ -f "pipes/$IMPL$phase.sh" ]; then
        exec "pipes/$IMPL$phase.sh" "$work"
    fi
    echo "  phaserun     $PIPE phase $phase has no program" >&2
    exit 2
fi

if [ -z "$PSOURCE" ]; then
    echo "  phaserun     the $PIPE pipeline names no single source a sweep can run on" >&2
    exit 2
fi
f=$work/$PSOURCE

state=.cache/state/$TAG$phase
rm -rf "$state"
mkdir -p "$state"
grep -c '' "$f" > "$state/input-lines"
tools/symbols.sh "$f" "$state/symbols"

"$edit" "$work" "$state"
tools/sweep.sh "$f"
"$check" "$work" "$state"

rm -rf "$state"
