#!/bin/sh
# Whim phase 17 -- the last two per-buffer encoding options.  See WHIM-GOAL.md.
#
# Usage: pipes/whim17-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# 'fileencoding' names the encoding a buffer was read in and will be written
# back in, and 'bomb' whether it had a byte-order mark.  With one encoding and no
# BOM, both have had one possible value since Phase 12 -- but unlike the six
# Phase 16 took, these are not plumbing: eight functions read them, and each had
# to be looked at.  buf_write() and readfile() take the buffer's encoding as a
# conversion target; bomb_size() reports how many bytes of the file are a BOM
# for the g CTRL-G count; save_file_ff() and file_ff_differs() remember the pair
# so :w can warn that they changed; g8 converts to the buffer's encoding to find
# a byte illegal in it; and add_b0_fenc() writes the name into a swap file's
# block zero, of which there have been none since Phase 11.
#
# What the options leave behind once nothing compares them is a pair of
# REMEMBERED COPIES in buf_T, written on every read and looked at by nobody.  A
# struct field is not a variable, so no warning reports it and the sweep cannot
# see it -- which is why those are listed in the tool rather than swept.
#
# 'fileformat', 'endofline' and 'endoffile' can still change under a buffer, so
# file_ff_differs() keeps those and loses only the two that cannot.
#
# THE DELTA: none.  Both options report E518 instead of a value with one
# possible setting, and what is left is 'encoding', alone, reporting utf-8.
set -eu

work=${1:?usage: whim17-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh nofenc "$f"
tools/st.sh dropoptions "$f" --local fileencoding bomb

# No sweep here.  One stood here, and the lines after it were written for swept text,
# but this phase and every stage it has run in reproduce their boundaries without
# it (WHIM-PLAN.md 2c; pipes/whim.stages) -- the stage's one sweep does its work.
tools/st.sh droplocal "$f" b_p_fenc b_p_bomb

# tools/phaserun.sh sweeps next, then runs pipes/whim17-check.sh.
