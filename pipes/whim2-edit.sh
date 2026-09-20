#!/bin/sh
# Whim phase 2 -- the options for features that are not here.  See WHIM-GOAL.md.
#
# Usage: pipes/whim2-edit.sh <work-dir> <state-dir>       (run from the repository root)
#
# Unlike phase 1, there are no commands to cut.  All fourteen `:menu` commands
# and all eight `:spell` ones are ALREADY `ex_ni` -- upstream's tiny
# configuration never compiled them, and the slim pipeline's empty-object prune
# removed their sources.  Checking that first is what stops this phase being
# busywork dressed as progress.
#
# What survived them is the SETTINGS.  Six spell options and one menu option are
# still in the table, still settable, still reported by `:set all` -- and read
# by nothing at all.  That is the same lie `:help` told in phase 1: a control
# the editor offers and cannot honour.  An embedded editor should say the option
# does not exist rather than accept a value and ignore it.
#
# `'mousemodel'` is NOT dropped, and the distinction is worth stating: it looks
# like a menu option and is not.  `:behave` sets it, and it selects how a mouse
# click behaves in a terminal, which this build still does.
#
# THE DELTA: `:set spell` and the six others become E518, and `:set all` stops
# listing them.  No Ex command changes -- they were already ex_ni -- so the
# cumulative list stays exactly what phase 1 left it, and the check below
# requires that rather than a new entry.
set -eu

work=${1:?usage: whim2-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- first: prove there is nothing to cut ---------------------------------
# If a menu or spell command ever acquires a real handler again, this phase is
# no longer the whole story and should say so rather than quietly do half of it.
live=$(tools/st.sh query whim2 "$f")
if [ -n "$live" ]; then
    echo "  commands     still implemented, so this phase is incomplete: $live"
    exit 1
fi
echo "  commands     all 24 menu and spell commands are already ex_ni"

# --- cut the settings, and let the sweep find the rest --------------------
tools/st.sh dropoptions "$f" \
    spell spellcapcheck spellfile spelllang spelloptions spellsuggest menuitems

# tools/phaserun.sh sweeps next, then runs pipes/whim2-check.sh.
