#!/bin/sh
# Whim phase 63 -- no jump list.  See WHIM-GOAL.md.
#
# Usage: pipes/whim63-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# The per-window jump list goes: w_jumplist, w_jumplistlen and w_jumplistidx,
# setpcmark() appending to it, CTRL-O and CTRL-I walking it through movemark(),
# :jumps and :clearjumps, cleanup_jumplist(), copying it to a new window and
# freeing it with one, and the loops that kept its marks right when lines moved
# or a file was forgotten.
#
# What stays, because it is not the jump list: the previous-context mark behind
# '' and `` (w_pcmark, still set by setpcmark()), the change list and g; g,
# (nv_pcmark() keeps that half), :keepjumps (it guards the pcmark and the change
# list too), and JUMPLISTSIZE, which sizes the change list.  CTRL-O in Select mode
# still runs one Visual command; anywhere else CTRL-O and CTRL-I beep.
#
# THE DELTA: :jumps and :clearjumps, now ex_ni.  The probes check CTRL-O no longer
# jumps back, '' still does, and :jumps is refused.
set -eu

work=${1:?usage: whim63-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim63 "$f"

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim63-check.sh.
