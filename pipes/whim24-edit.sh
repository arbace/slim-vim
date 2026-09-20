#!/bin/sh
# Whim phase 24 -- there is no mouse.  See WHIM-GOAL.md.
#
# Usage: pipes/whim24-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# A terminal mouse is a protocol, not a device: the terminal is asked to report
# clicks, it sends escape sequences, and the editor decodes them into key codes
# that the normal, insert and command-line loops dispatch like any other key.
# All four layers are here, and an editor driven from a keyboard needs none.
#
# THE ISLAND IS BOUNDED, which is what makes this a cut rather than a rewrite:
# thirty-five functions mention the mouse and all but two are reached only from
# each other, so funcreach.py deletes the interior once the roots are gone.
# `nomouse` removes only the roots -- the tables, the dispatch, the
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

work=${1:?usage: whim24-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh nomouse "$f"

tools/sweep.sh "$f"

tools/st.sh dropoptions "$f" --strict mouse mousefocus mousehide \
    mousemodel mousemoveevent mouseshape mousetime ttymouse

# tools/phaserun.sh sweeps next, then runs pipes/whim24-check.sh.
