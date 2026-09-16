#!/bin/sh
# Whim phase 29 -- :command, user-defined commands.  See WHIM-GOAL.md.
#
# Usage: pipes/whim29.sh <work-dir>      (run from the repository root)
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

work=${1:?usage: whim29.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/noucmd.py "$f"
python3 tools/retire.py "$f" command comclear delcommand


tools/sweep.sh "$f"

for g in do_ucmd uc_check_code uc_add_command b_ucmds ex_delcommand; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  ucmd         $g still has $n mentions after the sweep"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  ucmd         no user command table, and no dispatch into one"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear
