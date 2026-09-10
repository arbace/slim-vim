#!/bin/sh
# Run one phase, by program if there is one and by agent if there is not.
#
# Usage: tools/runphase.sh <phase> <workdir> <build-dir>
#
# Converting a phase is therefore adding a file: the day tools/phase4.sh
# appears, phase 4 stops being agent work and nothing else has to change.  That
# is the whole dispatch, and it is deliberately this dumb -- a table mapping
# phases to implementations would be a second place for the two to disagree.
set -eu

phase=${1:?usage: runphase.sh <phase> <workdir> <build-dir>}
work=${2:?}
build=${3:?}

start=$(date +%s)

if [ -x "tools/phase$phase.sh" ]; then
    kind=program
    "tools/phase$phase.sh" "$work"
else
    kind=agent
    tools/agentphase.sh "$phase" "$work"
fi

now=$(date +%s)
echo "$kind" > "$build/p$phase.kind"
echo "$((now - start))" > "$build/p$phase.seconds"
printf '  %-12s p%s by %s, %ss\n' "phase" "$phase" "$kind" "$((now - start))"
