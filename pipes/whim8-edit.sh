#!/bin/sh
# Whim phase 8 -- :! keeps its name and loses its process.  See WHIM-GOAL.md.
#
# Usage: pipes/whim8-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# `:!cmd`, `:[range]!cmd`, `:r !cmd`, `:w !cmd` and `:shell` keep their names,
# their ranges and their parsing.  What goes is everything under them -- the
# fork, the exec, the pipe, the wait -- and the temporary file with them,
# because a temp file is not interface.  It exists only because a Unix shell
# needs a file to read a range out of, and there is no longer a shell.
#
# THE PLACEMENT IS THE PHASE.  do_filter() calls vim_tempname() BEFORE it
# reaches mch_call_shell(), so stubbing the shell alone leaves the whole
# temporary-directory layer alive, assembling a file for a command that will
# never run.  Measured on a scratch build before this was written: cutting at
# mch_call_shell removes 6 libc symbols; cutting at do_filter/do_shell/
# get_cmd_output removes 16.
#
# This is also the seam to keep in mind for whatever comes after whim-vim.  An
# embedded editor with no process of its own may still be given a filter by its
# host, and do_filter() and do_shell() are exactly where that would attach --
# which is a reason to leave the two of them named and reporting rather than
# retired to ex_ni.
#
# THE DELTA: filtering and shelling out report "E319: Sorry, the command is not
# available in this version" instead of running anything.  :language completion
# stops listing locales, silently, because it got them from `locale -a`.
set -eu

work=${1:?usage: whim8-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut above the temp file ----------------------------------------------
tools/st.sh noshellout "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim8-check.sh.
