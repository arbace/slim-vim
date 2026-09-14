#!/bin/sh
# Whim phase 37 -- nothing in the file is unreachable, at the tip.
# See WHIM-GOAL.md.
#
# Usage: tools/whim37.sh <work-dir>      (run from the repository root)
#
# THE LAST PHASE, and the only one that removes nothing in particular.  Phase 28
# asserts the same invariant where it was first met; this one asserts it after
# everything, which is what makes it an invariant rather than a one-off.
#
# IT IS NOT A FORMALITY.  Enumerators and struct fields are the two kinds the
# per-phase sweep cannot see, so nine phases' worth of deletions accumulated
# behind it unnoticed: measured after phase 36, 42 dead struct fields and 12
# dead enumerators, none reachable and none reported by anything.
#
# The program is tools/unreachable.sh, shared with phase 28.
#
# THE DELTA: none of its own.
set -eu

tools/unreachable.sh "${1:?usage: whim37.sh <work-dir>}" \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear
