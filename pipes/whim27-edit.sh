#!/bin/sh
# Whim phase 27 -- `[[=a=]]` stops meaning "a with any accent".  See WHIM-GOAL.md.
#
# Usage: pipes/whim27-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# A POSIX bracket expression has three bracketed forms inside it, and they are
# three different features sharing a syntax:
#
#     [[:alpha:]]   a character CLASS     -- stays
#     [[.x.]]       a collating ELEMENT   -- stays
#     [[=a=]]       an equivalence CLASS  -- goes
#
# The third means "this character and every accented form of it", and expanding
# it takes reg_equi_class(), 1,397 LINES -- a switch over every base letter
# listing its variants across Latin-1 and Latin Extended-A and -B.  It is the
# largest single function left in the file, and it is reached only when a
# pattern contains `[=`.
#
# Two call sites and the sweep does the rest.  \w, \a and [[:alpha:]] are a
# different mechanism and are untouched.
#
# THE DELTA: none the harness records.  No behaviour case and no Ex command
# writes `[=` in a pattern -- which is the point.  The phase checks the change
# itself instead: `[[=a=]]` must stop matching an accented a and start matching
# the literal characters.
set -eu

work=${1:?usage: whim27-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh noequiclass "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim27-check.sh.
