#!/bin/sh
# Whim phase 20 -- nothing outside the process is consulted.  See WHIM-GOAL.md.
#
# Usage: tools/whim20.sh <work-dir>      (run from the repository root)
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

work=${1:?usage: whim20.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nohome.py "$f"
python3 tools/nogetenv.py "$f"


tools/sweep.sh "$f"
# The post-condition: after the sweep, no config path, no option and no
# environment name this phase removed is mentioned anywhere.  Asking before the
# sweep gets the wrong answer -- process_env is still there at that point and it
# is the sweep that removes it.
for g in 'getenv((char \*)((char_u \*)"HOME")' homedir init_users match_user getpwnam; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  globals      $g still has $n mentions after the sweep"
        echo "               a dropped row leaves its global uninitialised, and a"
        echo "               reader of it is a segfault before the first keystroke"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  home         nothing asks where home is, or who this is"

# The post-condition, asked AFTER the sweep for the reason above.
for g in getenv setenv unsetenv environ vim_getenv; do
    n=$(grep -cw -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  environment  $g still has $n mentions after the sweep"
        grep -nw -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  environment  nothing in the source asks the environment anything"


tools/phasecheck.sh "$work" "$f" .cache/symbols/before

# And the same question of the object, which is the one that cannot be argued
# with: a libc call this source no longer writes could still arrive through a
# macro or an inline.
for g in getenv setenv unsetenv environ; do
    if grep -qx -- "$g" .cache/symbols/last/undefined; then
        echo "  symbols      $g is still undefined in the object"
        exit 1
    fi
done
echo "  symbols      getenv, setenv, unsetenv and environ are gone from nm -u"

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, cumulative --------------------------------------------------
# --term-moved is CUMULATIVE, like the command list: the comparison is always
# against the slim baseline, and phase 19 collapsed that table for good.  Every
# phase after it declares the same thing.
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
