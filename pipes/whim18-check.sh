#!/bin/sh
# Whim phase 18, the check -- nothing is read at startup, and nothing on the command line decides anything any more.
# See pipes/whim18-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim18-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim18-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim18-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim18-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

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


tools/phasecheck.sh "$work" "$f" "$state/symbols"


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
