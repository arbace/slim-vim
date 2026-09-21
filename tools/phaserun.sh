#!/bin/sh
# Run a phase's tier-2 program.
#
# Usage: tools/phaserun.sh <pipeline> <phase> <work-dir>   (run from the root)
#        tools/phaserun.sh --parts <pipeline> <phase>
#
# The second form prints the phase's program file, and nothing for a phase that
# has none -- which is how memo.sh, implhash.sh, residue.sh and synth.sh ask "is
# this a program?" without each knowing where programs live.
#
# A phase program is pipes/<pipeline><N>.sh, run with the work dir.  Every slim
# phase is one, and so is anything tools/synth.sh writes.
#
# The whim and zero pipelines that grew out of this repository also have SPLIT
# phases -- an edit and a check with a shared sweep between, run in stages -- and
# this driver ran those too.  They moved to github.com/arbace/go-whim with the Go
# toolset that runs them; this repository keeps the shape slim uses.
set -eu

if [ "${1:-}" = "--parts" ]; then
    . tools/pipeline.sh "${2:?usage: phaserun.sh --parts <pipeline> <phase>}"
    p=${3:?usage: phaserun.sh --parts <pipeline> <phase>}
    if [ -f "pipes/$IMPL$p.sh" ]; then
        echo "pipes/$IMPL$p.sh"
    fi
    exit 0
fi

. tools/pipeline.sh "${1:?usage: phaserun.sh <pipeline> <phase> <work-dir>}"
p=${2:?usage: phaserun.sh <pipeline> <phase> <work-dir>}
work=${3:?usage: phaserun.sh <pipeline> <phase> <work-dir>}
if [ ! -f "pipes/$IMPL$p.sh" ]; then
    echo "  phaserun     $PIPE phase $p has no program" >&2
    exit 2
fi
exec "pipes/$IMPL$p.sh" "$work"
