#!/bin/sh
# Whim phase 22 -- the working directory is where it started.  See WHIM-GOAL.md.
#
# Usage: pipes/whim22-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# :cd, :lcd and :tcd are ex_ni, :! no longer forks, and nothing else in this
# editor moves the process.  So the directory it starts in is the one it dies
# in, and three pieces of machinery that exist because that was not true stop
# being needed:
#
#   * mch_FullName() chdir'd into the leading directory of a relative name,
#     asked getcwd() where that landed, and chdir'd back -- via fchdir() on a
#     descriptor it held open, falling back to chdir().  That is what resolved
#     `..` and a symlinked directory on the way to a full name.  FCHDIR.
#   * win_fix_current_dir() restores a window's or tab's local directory, and
#     runs only when w_localdir, tp_localdir or globaldir is set.  The first two
#     come only from :lcd and :tcd; globaldir is assigned only inside this
#     function.  Unreachable.
#   * edit_buffers() takes a cwd to return to between -o windows, and is passed
#     start_dir -- `static char_u *start_dir = NULL;`, which nothing assigns.
#     CHDIR, once mch_chdir() has no callers left.
#
# WHAT IT COSTS, which is why this is a phase and not a cleanup: a full name is
# now the working directory with the name appended, so `../x/y` becomes
# /cwd/../x/y rather than /real/x/y.  It opens the same file; what it loses is
# that two spellings of one path no longer compare equal, so `:e ../x/y` and
# `:e /real/x/y` are two buffers rather than one.
#
# getcwd STAYS, and is now asked once.  shorten_fnames() shortens every
# displayed name against it and mch_FullName() is how a relative name becomes
# absolute at all -- dropping it would mean b_ffname could not be a full path,
# which is a capability cut rather than plumbing.  Since nothing can move the
# process, the answer cannot change: it is read into a static on the first call.
#
# THE DELTA: none the harness records.
set -eu

work=${1:?usage: whim22-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh nochdir "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim22-check.sh.
