#!/bin/sh
# Whim phase 18 -- nothing is read at startup, and nothing on the command line
# decides anything any more.  See WHIM-GOAL.md.
#
# Usage: tools/whim18.sh <work-dir>      (run from the repository root)
#
# TWO CUTS IN ONE PHASE, and they are one question: what may the invocation
# say?
#
# THE FILES.  source_startup_scripts() looked for a vimrc in five places, an
# exrc in the current directory, and a plugin in every directory of
# 'runtimepath'.  It now reads the file it was told to read on the command line
# and nothing else, and 'exrc' -- the option that let a directory carry its own
# configuration -- goes with it.
#
# THE FLAGS.  What is left of the command line is what the flags still decide,
# and several of them no longer decide anything: -y and -Z chose modes whose
# machinery has gone, and 'viminfo' and 'viminfofile' name a file nothing reads
# or writes.
#
# THEY ARE ONE PHASE because the second is what the first leaves behind: a flag
# is only pointless once the thing it selected is gone.
#
# THE DELTA: none the harness records.  A harness passes its own -c and -u.
set -eu

work=${1:?usage: whim18.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nostartup.py "$f"
python3 tools/dropoptions.py "$f" --strict exrc
python3 tools/dropopts.py "$f" -y -Z
python3 tools/nocmdopts.py "$f"
python3 tools/dropoptions.py "$f" --strict viminfo viminfofile


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


tools/phasecheck.sh "$work" "$f" .cache/symbols/before


tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
