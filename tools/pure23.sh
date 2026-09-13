#!/bin/sh
# Pure phase 23 -- there is no home directory.  See PURE-GOAL.md.
#
# Usage: tools/pure23.sh <work-dir>      (run from the repository root)
#
# $HOME is where an editor keeps the things it was told not to keep: this fork
# stopped writing them in phase 13 and stopped looking for them in phase 20, and
# what is left is the NOTION of a home directory -- ~/x meaning a path, ~bob
# meaning someone else's, and /home/you/x displayed back as ~/x.
#
# All three go, and the last is why this is not only a getenv removal:
# home_replace() has thirteen callers, every one a place that shows the user a
# file name.  It becomes a bounded copy, so the thirteen keep working and a name
# is shown as what it is.
#
# The user database goes with them -- init_users(), add_user(), match_user() and
# get_users() exist so ~bob can complete, and mch_get_uname() so a swap file
# could say who wrote it.
#
# THIS IS WHERE THE SYMBOL COUNT MOVES, four of the five expected:
# getpwnam, getpwent, setpwent, endpwent.  CLAUDE.md notes that getpwnam()
# working under static musl is one of the two things that make this binary
# honestly standalone; it no longer needs it.
#
# TWO CORRECTIONS TO WHAT THIS PHASE WAS PLANNED TO DO.  getuid and getgid do
# NOT go: buf_write() uses them to check ownership before overwriting a
# read-only file and to preserve owner and group, which is file writing and
# stays.  And getpwuid does not go either -- mch_get_uname() is still reached
# from swapfile_info(), under `-r`, which lists swap files that cannot exist.
# That is phase 13's leftover and wants a phase of its own: ml_recover alone is
# 559 lines.
#
# THE DELTA: none the harness records.  `:e ~/notes` opens a file called
# ~/notes in the current directory, which no harness asks for.
set -eu

work=${1:?usage: pure17.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nohome.py "$f"


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

tools/canon.sh "$f"



tools/phasecheck.sh "$work" "$f" .cache/symbols/before

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# --- the delta, cumulative --------------------------------------------------
# --term-moved is CUMULATIVE, like the command list: the comparison is always
# against the slim baseline, and phase 22 collapsed that table for good.  Every
# phase after it declares the same thing.
tools/puredelta.sh "$work/pure-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
