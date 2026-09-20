#!/bin/sh
# Whim phase 11 -- nothing is written that was not asked for.  See WHIM-GOAL.md.
#
# Usage: pipes/whim11-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# A swap file is not a recovery add-on bolted to the side of the editor; it is
# MEMLINE'S BACKING STORE, created beside every file you open, written to as you
# type, deleted on a clean exit.  For an embedded editor it is the last thing
# writing a file nobody asked for, and it is why 'directory' is searched for a
# free .swp name and why a 576-line recovery reader exists.
#
# What goes is the FILE, not the memline.  mf_open() already supports a memfile
# with no name -- that is what `:set noswapfile` has always produced -- so the
# buffer keeps its block structure and never acquires a fd.  The cost is real
# and was agreed before this was written: NO CRASH RECOVERY, and a buffer larger
# than memory can no longer page out to disk.
#
# With it go the two other things that write without being asked: :mkvimrc,
# :mkexrc, :mksession and :mkview, which drop a script into the current
# directory, and :checktime, which stats a file behind the user's back.
#
# NOT done here, and worth saying: the AUTOMATIC timestamp check remains.
# check_timestamps() is still called from main_loop(), edit() and wait_return(),
# so the editor still notices a file changing underneath it -- retiring
# :checktime removes the command, not the polling.  That is a separate cut with
# a separate delta.
#
# THE DELTA: eight command names report that they are not available.
# 'updatecount' and 'swapsync' stop existing; 'directory' CANNOT go here, since
# recover_names() scans it for swap files until phase 21, and dropping its row
# while a reader survives is what left p_dir NULL and made `:w!` over an
# existing other file segfault for twelve phases.  'swapfile' cannot
# go -- it is PV_BUF and its row is what initialises the global -- so it stays
# and is now always effectively off.
set -eu

work=${1:?usage: whim11-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh noswap "$f"
tools/st.sh retire "$f" recover preserve swapname \
    mkvimrc mkexrc mksession mkview checktime
tools/st.sh dropoptions "$f" updatecount swapsync

# tools/phaserun.sh sweeps next, then runs pipes/whim11-check.sh.
