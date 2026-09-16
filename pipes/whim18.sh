#!/bin/sh
# Whim phase 18 -- nothing is read at startup, and nothing on the command line
# decides anything any more.  See WHIM-GOAL.md.
#
# Usage: pipes/whim18.sh <work-dir>      (run from the repository root)
#
# TWO CUTS IN ONE PHASE, and they are one question: what may the invocation
# say?
#
# THE FILES.  source_startup_scripts() looked for a vimrc in five places, an
# exrc in the current directory, and a plugin in every directory of
# 'runtimepath'.  It reads nothing at all now -- not even a file named with -u,
# which goes too -- and 'exrc', the option that let a directory carry its own
# configuration, goes with it.
#
# -u GOES HERE, not later, so that no tool depends on it.  -u NONE was how a
# harness kept a vimrc out of a recorded run; once nothing is searched for, it
# is a no-op, and every harness now isolates the editor with an empty $HOME,
# $VIM and $VIMRUNTIME instead, which holds for slim-vim too.
#
# THE FLAGS.  What is left of the command line is what the flags still decide,
# and several of them no longer decide anything: -y and -Z chose modes whose
# machinery has gone, and 'viminfo' and 'viminfofile' name a file nothing reads
# or writes.
#
# THEY ARE ONE PHASE because the second is what the first leaves behind: a flag
# is only pointless once the thing it selected is gone.
#
# THE DELTA: none the harness records.  No harness passes -u.
set -eu

work=${1:?usage: whim18.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nostartup.py "$f"
python3 tools/dropoptions.py "$f" --strict exrc
python3 tools/dropopts.py "$f" -y -Z -u
python3 tools/nocmdopts.py "$f"
python3 tools/dropoptions.py "$f" --strict viminfo viminfofile


tools/sweep.sh "$f"
# The post-condition: after the sweep, no config path, no option and no
# environment name this phase removed is mentioned anywhere.  Asking before the
# sweep gets the wrong answer -- process_env is still there at that point and it
# is the sweep that removes it.
for g in p_exrc process_env set_init_xdg_rtp source_startup_scripts '"VIMINIT"' '"EXINIT"' '"XDG_CONFIG_HOME"'; do
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

# -u must now be what any unknown option is, and the control must still run.
out=$(cd "$work" && ./whim-vim -e -s -c 'qa!' </dev/null 2>&1) && rc=0 || rc=$?
[ "$rc" = 0 ] || { echo "  cli          the control failed: -e -s -c qa! exits $rc: $out"; exit 1; }
out=$(cd "$work" && ./whim-vim -u NONE -e -s -c 'qa!' </dev/null 2>&1) && rc=0 || rc=$?
case "$out" in
    *"Unknown option argument"*) [ "$rc" = 1 ] || { echo "  cli          -u exits $rc, expected 1"; exit 1; } ;;
    *) echo "  cli          -u is not refused as unknown (exit $rc): $out"; exit 1 ;;
esac
echo "  cli          -u is an unknown option"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
