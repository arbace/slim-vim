#!/bin/sh
# Whim phase 29 -- :command, user-defined commands.  See WHIM-GOAL.md.
#
# Usage: pipes/whim29-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# 1,451 lines: a parser for -nargs/-range/-complete/-bang, a per-buffer and a
# global growable array of definitions, uc_check_code() expanding <args>,
# <q-args>, <line1>, <count>, <bang>, <reg> and <mods>, and a listing mode.
#
# WITHOUT +eval a user command can only invoke built-in commands, which makes it
# a way of writing an alias -- and this editor reads no vimrc, so the only way
# to define one is to type :command in the session where it is used.
#
# THE DELTA IS REAL, and is TWO names rather than the three retired.  :command
# with no arguments lists what is defined, and :comclear clears it: both succeed
# today, so both move.  :delcommand does NOT -- it is EX_NEEDARG, so the sweep's
# bare call already failed, and retiring a command only shows in the sweep if it
# used to succeed.  Declaring three and getting two is the check working.
set -eu

work=${1:?usage: whim29-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh noucmd "$f"
tools/st.sh retire "$f" command comclear delcommand

# tools/phaserun.sh sweeps next, then runs pipes/whim29-check.sh.
