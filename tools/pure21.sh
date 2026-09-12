#!/bin/sh
# Pure phase 21 -- command-line options that no longer decide anything.
# See PURE-GOAL.md.
#
# Usage: tools/pure21.sh <work-dir>      (run from the repository root)
#
# Four options outlived what they controlled, each in a different way.
#
#   -y  evim mode.  parmp->evim_mode is assigned and read nowhere: its one
#       reader was the line in source_startup_scripts() that sourced
#       $VIMRUNTIME/evim.vim, and phase 20 removed it.
#   -Z  restricted mode, whose whole purpose is to refuse shell commands.
#       check_restricted() has two callers left -- do_bang(), stubbed in phase
#       10, and ex_stop() -- and no LIVE command carries EX_RESTRICT: the ten
#       that do are all ex_script_ni.  It guards nothing.
#   -t  jump to a tag at startup, by running `:ta <tag>`.  Phase 12 retired
#       :tag, so the option's whole effect is to run a command that reports it
#       is not implemented.
#   -i  the viminfo file.  'viminfo' and 'viminfofile' are wired to
#       (char_u *)NULL in BOTH editors -- the tiny configuration has no viminfo
#       at all -- so `-i NONE` has been a no-op for as long as this fork has
#       existed.  That is why the harnesses passed it without anyone noticing.
#
# -u <file> STAYS.  Phase 20 removed every path the editor searched on its own;
# a file the user names is not the editor going looking.
#
# THE HARNESSES CHANGE, and that is the check rather than a side effect.  All
# three stop passing -i NONE, and slim-vim -- which still has the option -- must
# still match its recorded baselines afterwards.  It does, which is what proves
# the option was a no-op there too rather than merely here.
#
# THE DELTA: none.
set -eu

work=${1:?usage: pure17.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/dropopts.py "$f" -y -Z
python3 tools/nocmdopts.py "$f"
python3 tools/dropoptions.py "$f" --strict viminfo viminfofile


tools/sweep.sh "$f"

# The post-condition: after the sweep, no config path, no option and no
# environment name this phase removed is mentioned anywhere.  Asking before the
# sweep gets the wrong answer -- process_env is still there at that point and it
# is the sweep that removes it.
for g in evim_mode check_restricted EX_RESTRICT restricted '"vif"'; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  globals      $g still has $n mentions after the sweep"
        echo "               a dropped row leaves its global uninitialised, and a"
        echo "               reader of it is a segfault before the first keystroke"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  options      nothing names the four, or what they set"

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
tools/puredelta.sh "$work/pure-vim" "$f" --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
