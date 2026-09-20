#!/bin/sh
# Whim phase 16 -- six options that no longer decide anything.  See WHIM-GOAL.md.
#
# Usage: pipes/whim16-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# 'path' and 'suffixesadd' have been inert since the file finder went, 'tags'
# and 'tagcase' since the tag stack, 'autoread' since the timestamp poll, and
# 'swapfile' since the swap file.  All six are still here, because a row is what
# initialises its global and `dropoptions` refuses to leave one dangling
# -- Phase 10's trap, which this phase finally clears rather than works around.
#
# THE ORDER IS THE PHASE, and it is forced rather than chosen:
#
#   1. the three readers that are not plumbing (`noinertopts`)
#   2. the rows, with --local (`dropoptions`)
#   3. SWEEP -- which is what removes did_set_tagcase() and did_set_swapfile(),
#      the option callbacks, reachable only from the rows
#   4. the buffer fields and their plumbing (`droplocal`)
#   5. sweep again
#
# Steps 3 and 4 cannot swap.  The callbacks read the buffer field, so removing
# the field first stops the file compiling; the sweep works by reading gcc's
# warnings, so a file that does not compile is a file the sweep cannot act on,
# and the callbacks would stay for ever.
#
# THE DELTA: none.  All six options report E518 instead of a value that decided
# nothing.
set -eu

work=${1:?usage: whim16-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh noinertopts "$f"
tools/st.sh dropoptions "$f" --local \
    path suffixesadd tags tagcase autoread swapfile

tools/sweep.sh "$f"
tools/st.sh droplocal "$f" b_p_path b_p_sua b_p_tags b_p_tc b_p_ar b_p_swf

# tools/phaserun.sh sweeps next, then runs pipes/whim16-check.sh.
