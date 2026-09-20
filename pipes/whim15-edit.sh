#!/bin/sh
# Whim phase 15 -- the last two encoding options.  See WHIM-GOAL.md.
#
# Usage: pipes/whim15-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Phase 12 emptied 'fileencodings' and said so.  It was true at startup and not
# afterwards: set_option_default() special-cases the option, so `:set fencs&`
# restored ucs-bom,utf-8,default,latin1 from fencs_utf8_default -- a third
# reference that phase did not find, because it names the STRING rather than the
# function the other two called.  Measured on the shipped binary: fileencodings=
# at startup, fileencodings=ucs-bom,utf-8,default,latin1 after a reset.
#
# Three readers go, and with them the two options can finally follow:
# set_option_default() stops special-casing 'fileencodings', which is what makes
# Phase 12's claim true at every moment rather than one; readfile() stops
# choosing between an empty list and a list to walk, and takes the buffer's own
# 'fileencoding', which is the branch the empty case already took; and
# did_set_encoding() stops setting up a conversion between 'termencoding' and
# 'encoding', which convert_setup() has answered CONV_NONE to since Phase 12.
#
# 'encoding' STILL cannot go, and this is where that stops being temporary:
# p_enc is the NAME of the one encoding, compared against in twenty-nine places.
# Removing the option would mean removing the name, and the name does work.
#
# THE DELTA: none.  `:set fencs&` no longer restores a list of encodings this
# build cannot convert between, which is a correction rather than a change.
set -eu

work=${1:?usage: whim15-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh nofencs "$f"

# No sweep here.  One stood here, and the lines after it were written for swept text,
# but this phase and every stage it has run in reproduce their boundaries without
# it (WHIM-PLAN.md 2c; pipes/whim.stages) -- the stage's one sweep does its work.
tools/st.sh dropoptions "$f" --strict fileencodings termencoding

# tools/phaserun.sh sweeps next, then runs pipes/whim15-check.sh.
