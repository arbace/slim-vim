#!/bin/sh
# Whim phase 34 -- no abbreviations.  See WHIM-GOAL.md.
#
# Usage: pipes/whim34-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# An abbreviation is a word the editor rewrites as you type it.  Nothing reads a
# vimrc here, so the only way to get one was to type :abbreviate in the session
# that wanted it; the twelve rows that did that go to ex_ni, and
# `noabbr` removes the questions insert mode and the command line kept
# asking about abbreviations that can no longer exist.  The sweep takes the
# rest: check_abbr() and its wrappers, ex_abbreviate and ex_abclear.
#
# THE DELTA: the nine rows that succeeded run bare -- :abbreviate, :noreabbrev
# and :abclear, with their `i` and `c` forms, which listed or cleared nothing
# and exited 0.  The three :unabbreviate rows already failed with no argument.
# No behaviour case types an abbreviation.
set -eu

work=${1:?usage: whim34-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- the rows, then the questions ------------------------------------------
tools/st.sh retire "$f" abbreviate noreabbrev unabbreviate abclear \
    iabbrev inoreabbrev iunabbrev iabclear cabbrev cnoreabbrev cunabbrev cabclear
tools/st.sh noabbr "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim34-check.sh.
