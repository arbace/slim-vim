#!/bin/sh
# stages' FAILURE paths, on whim -- which has real multi-phase stages, so the
# constraints can actually be violated.  (Zero has one stage per phase, so
# `apart` and `need swept` are unfalsifiable there: the first attempt at this
# control produced empty output from both sides and proved nothing.)
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
orig=${GOCMP:-tools/gocmp}/whim.stages.orig
cp pipes/whim.stages "$orig"
restore() { cp "$orig" pipes/whim.stages; }
trap restore EXIT

try() {
    a=$(sh tools/stages.sh whim --check 2>&1 || echo "EXIT$?")
    b=$(./"$bin" stages whim --check 2>&1 || echo "EXIT$?")
    if [ "$a" = "$b" ]; then
        printf '=== %-22s SAME ===\n%s\n' "$1" "$a"
    else
        printf '=== %-22s DIFFER ===\nshell:\n%s\ngo:\n%s\n' "$1" "$a" "$b"
    fi
    restore
}

# 13 and 14 share stage 13-41, so requiring them apart must fail.
restore; echo 'apart 13 14' >> pipes/whim.stages
try "violated apart"

# 20 sits inside 13-41 and does not start it.
restore; echo 'need 20 swept' >> pipes/whim.stages
try "need swept mid-stage"

# A phase covered twice.
restore; echo 'stage       72' >> pipes/whim.stages
try "phase covered twice"
