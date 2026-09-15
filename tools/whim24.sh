#!/bin/sh
# Whim phase 24 -- there is no mouse.  See WHIM-GOAL.md.
#
# Usage: tools/whim24.sh <work-dir>      (run from the repository root)
#
# A terminal mouse is a protocol, not a device: the terminal is asked to report
# clicks, it sends escape sequences, and the editor decodes them into key codes
# that the normal, insert and command-line loops dispatch like any other key.
# All four layers are here, and an editor driven from a keyboard needs none.
#
# THE ISLAND IS BOUNDED, which is what makes this a cut rather than a rewrite:
# thirty-five functions mention the mouse and all but two are reached only from
# each other, so funcreach.py deletes the interior once the roots are gone.
# tools/nomouse.py removes only the roots -- the tables, the dispatch, the
# decoder, setmouse()'s 31 bare calls, and the three conditions outside the
# island that asked whether the mouse was enabled.
#
# THE EIGHT OPTIONS GO AFTER THE SWEEP, under --strict, which is what proves
# nothing reads their globals any anymore.  Asking before it is the mistake this
# pipeline keeps relearning.
#
# THE KE_* AND KS_* ENUMERATORS STAY: they are constants, they cost nothing, and
# deleting an enumerator renumbers every one after it -- several enums here
# index a parallel table.
#
# THE DELTA: none the harness records.  No Ex command is a mouse command, no
# behaviour case clicks, and the pty harness types keys.
set -eu

work=${1:?usage: whim24.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nomouse.py "$f"


tools/sweep.sh "$f"

python3 tools/dropoptions.py "$f" --strict mouse mousefocus mousehide \
    mousemodel mousemoveevent mouseshape mousetime ttymouse
tools/sweep.sh "$f"

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


tools/phasecheck.sh "$work" "$f" .cache/symbols/before

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

# The mouse rows of nv_cmds[] share a table with every other key.  Normal mode
# reaches that table through a precomputed index, so a cut there shows up as
# arrows that do nothing -- which this phase once shipped.
python3 tools/arrowcheck.py "$work/whim-vim"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
