#!/bin/sh
# Whim phase 31 -- file-name modifiers.  See WHIM-GOAL.md.
#
# Usage: pipes/whim31-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# eval_vars() expands % and # into the current and alternate file names, and
# <cword>, <afile> and the others.  THAT STAYS -- `:w %` and `:e #` are how a
# file name is written without typing it.
#
# What goes is the SUFFIX LANGUAGE that may follow: modify_fname(), 426 lines
# implementing :p :h :t :r :e :s/from/to/ :gs :~ and :., applied left to right so
# that %:p:h:t means something.  Most of it answers questions this editor can no
# longer ask -- :p made a name absolute by asking where the working directory
# is, and phase 22 fixed that to one answer; :~ shortened a name under $HOME,
# and phase 20 removed the notion of a home directory.
#
# THE DELTA: none the harness records.  The phase checks the two halves itself:
# `:w %` must still write the current file, and `%:t` must stop being a tail.
set -eu

work=${1:?usage: whim31-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh nofnamemod "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim31-check.sh.
