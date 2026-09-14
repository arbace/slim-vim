#!/bin/sh
# Whim phase 28 -- nothing in the file is unreachable.  See WHIM-GOAL.md.
#
# Usage: tools/whim28.sh <work-dir>      (run from the repository root)
#
# THE FIRST OF TWO.  This clears the backlog -- 82 dead enumerators and 77 dead
# struct fields, two kinds nothing else in either pipeline looks at -- and
# tools/whim37.sh asserts the same invariant again at the tip, because every
# phase after this one deletes code that can orphan more.  The program is
# tools/unreachable.sh, called by both, so the invariant cannot drift between
# the two places it is checked.
#
# THE DELTA: none of its own.
set -eu

tools/unreachable.sh "${1:?usage: whim28.sh <work-dir>}" \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
