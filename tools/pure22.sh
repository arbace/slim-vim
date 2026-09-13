#!/bin/sh
# Pure phase 22 -- the terminal is what the build says.  See PURE-GOAL.md.
#
# Usage: tools/pure22.sh <work-dir>      (run from the repository root)
#
# Five environment variables describe the terminal and the editor believes all
# of them: $TERM picks a capability table, $LINES and $COLUMNS override the size
# the kernel reports, $COLORS overrides the colour count the table gives, and
# $COLORFGBG is read for the background.
#
# THE COMPILED NAME IS xterm-256color, NOT xterm, and that is the whole care in
# this phase.  Measured on the shipped binary before choosing:
#
#     TERM=xterm-256color   -> term=xterm-256color  t_Co=256
#     TERM=xterm            -> term=xterm           t_Co=8
#     TERM= (unset)         -> term=xterm           t_Co=8
#
# set_termname() keeps the requested name and tests strstr(requested, "256color")
# to apply builtin_256colors on top of whichever table it chose.  So the obvious
# fallback -- the one the unset case already took -- would have cost eight of
# every nine colours the terminal can show, silently, for nothing.
# xterm-256color resolves to the same builtin_xterm table and keeps the add-on.
#
# -T <term> STAYS.  It is not the environment, and with one compiled default it
# is the only way left to say "this is a dumb terminal".  The ten built-in
# entries are still there and -T still reaches them.
#
# THE DELTA: the terminal table collapses.  Every TERM resolved to its own row
# before; now every one of them resolves to xterm-256color with 256 colours,
# because nothing consults TERM.  That is declared with --term-moved, which
# puredelta.sh grew for this phase -- until now no phase could move that table,
# so "expected unchanged" was the whole check.
set -eu

work=${1:?usage: pure17.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/noterm.py "$f"


tools/sweep.sh "$f"

# The post-condition: after the sweep, no config path, no option and no
# environment name this phase removed is mentioned anywhere.  Asking before the
# sweep gets the wrong answer -- process_env is still there at that point and it
# is the sweep that removes it.
for g in 'getenv((char \*)((char_u \*)"TERM")' 'getenv("LINES")' 'getenv("COLUMNS")' 'getenv((char \*)((char_u \*)"COLORS")'; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  globals      $g still has $n mentions after the sweep"
        echo "               a dropped row leaves its global uninitialised, and a"
        echo "               reader of it is a segfault before the first keystroke"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  terminal     nothing asks the environment what terminal this is"

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
tools/puredelta.sh "$work/pure-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
