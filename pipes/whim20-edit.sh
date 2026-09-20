#!/bin/sh
# Whim phase 20 -- nothing outside the process is consulted.  See WHIM-GOAL.md.
#
# Usage: pipes/whim20-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# TWO CUTS IN ONE PHASE, and the second finishes a function the first cuts in
# half.
#
# THERE IS NO HOME DIRECTORY.  `$HOME` is where an editor keeps the things it
# was told not to keep; phase 11 stopped writing them and phase 18 stopped
# looking for them, and what is left is the NOTION -- `~/x` meaning a path,
# `~bob` meaning someone else's, and `/home/you/x` displayed back as `~/x`.
# home_replace() has thirteen callers, every one a place that shows the user a
# file name, so it becomes a bounded copy rather than going.  The password
# database goes with it: getpwnam, getpwent, setpwent, endpwent.
#
# AND NOTHING IS READ FROM THE ENVIRONMENT.  vim_getenv() was already half dead
# -- phase 1 folded its `vimruntime` flag to FALSE -- so it CAN ONLY EVER ANSWER
# "not set", and every caller collapses to the branch it was already taking:
# $VAR in a file name, $PATH, $VIMRUNTIME, $SHELL, $CDPATH, $TMPDIR, $VIM_POSIX,
# $COLORFGBG, $TZ, and the $VIM/$VIMRUNTIME/$MYVIMDIR that vimrc_found() used to
# publish -- itself unreachable since phase 18.
#
# THEY ARE ONE PHASE because expand_env_esc() handles `~` and `$VAR` in one
# loop: the first cut takes the `~` half and the second takes the `$` half, and
# what is left is skipwhite, the backslash escape and the bound on dstlen.
#
# THE CHECK IS THE OBJECT: getenv, setenv, unsetenv and environ leave `nm -u`.
# Grepping the source is not enough -- the sweep is what removes vim_getenv,
# and asking before it runs gets the wrong answer.
#
# WHAT STAYS: vim_localtime() still calls localtime_r(), and musl reads $TZ
# inside it.  The rule is that THIS SOURCE asks the environment nothing.
#
# THE DELTA: none the harness records.
set -eu

work=${1:?usage: whim20-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh nohome "$f"
tools/st.sh nogetenv "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim20-check.sh.
