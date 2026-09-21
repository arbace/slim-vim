#!/bin/sh
# Zero phase 45's check -- fold the node types.
#
# Usage: pipes/zero45-check.sh <work-dir> <state-dir>   (run from the repository root)
#
# THE DECLARED DELTA IS NOTHING AT ALL AND IT IS ZERO PHASES 14, 15 AND 44'S WEAKEST
# KIND.  The code changes, the binary moves, and the claim is that a replacement does
# what the thing it replaces did.  There is no `cmp` to be had: every block in the
# editor is allocated differently, reached differently and tagged differently.  So the
# recordings are the floor and not the evidence, and what carries the phase is twelve
# builds of its own output with one thing changed -- nine that MUST move a recording
# and three that are MEASURED not to, each of the three with the reason written beside
# it and, for the one that matters most, a second measurement that shows what it DID
# move.
#
# WHAT IS CHECKED, in the order it is cheapest to fail:
#
#   1  the product builds from a tree the clean really emptied
#   2  THE PARTITION, and it is a partition over the file's WHOLE VOCABULARY: exactly
#      29 identifiers leave and exactly 5 arrive, string literals excluded, and each
#      side is accounted for name by name -- 25 the edit takes, 2 the sweep takes, 2
#      that go with a function this phase deletes, and the five the fold writes
#   3  the representation, read out of the output, and SIZEOF(PTR_EN) == 16 COMPILED
#      AGAINST BOTH CUTS -- the input's and the output's -- because the tree's fanout
#      is computed from it and the corpus's root-split coverage rests on the fanout
#   4  one allocation per node, at its own size, stated as a partition over every
#      allocation the memline makes
#   5  two full recordings, byte for byte the input's, and identical to each other
#   6  the corpus REACHES the tree exactly as it did, marker by marker and case by case
#   7  what the node costs the arena, measured on both sides
#   8  the controls
#   9  ZERO PHASE 44'S PREDICTION, MEASURED: its own capacity control, built from this
#      phase's input and from its output in the same run
#  10  nm -u unchanged both ways, the cut, and the ordinary phase checks
#
# WHY SECTION 3 COMPILES SOMETHING RATHER THAN READING IT.  `pb_count_max` was
# `(page - offsetof(PTR_BL, pb_pointer)) / sizeof(PTR_EN)` and is now the enumerator
# PB_COUNT_MAX; the two agree at 255 only because `PTR_EN` is still 16 bytes.  At 8 the
# fanout would be 511, `mem_deep_jumps`'s 391 data blocks would fall under it, and the
# ONE case of sixteen that reaches a root split would stop reaching it -- while every
# recording still matched and every check still passed.  That is the defect zero phase
# 40 exists to have ended, so it is asserted in the source, compiled on both sides, and
# then MEASURED in section 6 and demonstrated by a control in section 8.

# THE BODY IS GO: tools/go/internal/check/zero45.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero45-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero45-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero45 "$work" "$state"
