#!/bin/sh
# What a phase is called, from the document that defines it.
#
# Usage: tools/phasename.sh <phase>
#
# SLIM-GOAL.md's headings are the only place the ten phases are named, so the
# progress log reads them from there rather than keeping a second list that can
# disagree with the first.
set -eu

phase=${1:?usage: phasename.sh <phase>}
sed -n "s/^## Phase $phase [—-] *//p" SLIM-GOAL.md | head -1
