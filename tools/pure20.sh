#!/bin/sh
# Pure phase 20 -- nothing is read at startup that was not named on the command
# line.  See PURE-GOAL.md.
#
# Usage: tools/pure20.sh <work-dir>      (run from the repository root)
#
# An editor that goes looking for its own configuration has a filesystem layout
# in its head.  source_startup_scripts() tried, in order: $VIMRUNTIME/evim.vim,
# $VIMRUNTIME/defaults.vim, $VIM/vimrc, $VIMINIT, $HOME/.vimrc, $HOME/.exrc,
# and -- with 'exrc' on -- ./.vimrc and ./.exrc in whatever directory it was
# started in, each guarded by an ownership check, because reading a config file
# out of the current directory is a way to be handed someone else's commands.
#
# All of it goes.  `-u <file>` STAYS, and so does :source: a file the user names
# is not the editor going looking, and Phase 12 already decided :source stays.
# NONE, NORC and DEFAULTS are still recognised and still mean "read nothing",
# which they now do by agreeing with everything else.
#
# set_init_xdg_rtp() goes with them -- it built a 'runtimepath' out of
# $XDG_CONFIG_HOME, and Phase 1 emptied that option while this was still filling
# it back in -- and process_env(), which ran $VIMINIT or $EXINIT as Ex commands.
#
# 'exrc' is dropped: it selected between two searches that no longer happen.
#
# THE DELTA: none, and that is the point rather than a surprise.  Every harness
# already passes -u NONE, so none of these paths was taken in a recorded run.
# What changes is that the editor no longer needs to be told.
set -eu

work=${1:?usage: pure17.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nostartup.py "$f"
python3 tools/dropoptions.py "$f" --strict exrc


tools/sweep.sh "$f"

# The post-condition: after the sweep, no config path, no option and no
# environment name this phase removed is mentioned anywhere.  Asking before the
# sweep gets the wrong answer -- process_env is still there at that point and it
# is the sweep that removes it.
for g in p_exrc process_env set_init_xdg_rtp '"VIMINIT"' '"EXINIT"' '"XDG_CONFIG_HOME"'; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  globals      $g still has $n mentions after the sweep"
        echo "               a dropped row leaves its global uninitialised, and a"
        echo "               reader of it is a segfault before the first keystroke"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  startup      no config path, option or environment name is left"

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
