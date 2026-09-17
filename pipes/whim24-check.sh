#!/bin/sh
# Whim phase 24, the check -- there is no mouse.
# See pipes/whim24-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim24-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim24-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim24-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim24-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The post-condition: no mouse function, no mouse option, no mouse key name.
for g in 'do_mouse' 'jump_to_mouse' 'setmouse' 'mouse_has' 'nv_mouse' \
         'check_termcode_mouse' 'p_mouse' 'ttymouse' '"LeftMouse"' \
         'ScrollWheelUp' 'WaitForCharOrMouse'; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  mouse        $g still has $n mentions after the sweep"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  mouse        no handler, no option, no key name, no protocol"


tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# `:set mouse=a` must now fail.  CHECK WHAT IT DID, NOT WHAT IT SAID -- silent
# Ex mode prints nothing, so a first version read an empty message and called it
# a failure.  Nor does a failing `-c` abandon the ones after it: `set nosuchopt`
# followed by `w` still writes the file, so "did the file appear" is not the
# answer either.  The exit status is: 0 for an option that exists, 1 for one
# that does not.  The control is what makes that a check rather than a
# tautology -- it fails if the binary exits 1 no matter what it is asked.
probe() {
    (cd "$work" && ./whim-vim -e -s -c "set $1" -c 'qa!' </dev/null \
        >/dev/null 2>&1)
    echo $?
}
if [ "$(probe ignorecase)" != 0 ]; then
    echo "  options      the control failed: :set ignorecase exits non-zero too"
    exit 1
fi
if [ "$(probe mouse=a)" = 0 ]; then
    echo "  options      :set mouse=a was accepted, so the option is still there"
    exit 1
fi
echo "  options      :set mouse=a is refused, :set ignorecase still taken"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
