#!/bin/sh
# Pure phase 2 -- the options for features that are not here.  See PURE-GOAL.md.
#
# Usage: tools/pure2.sh <work-dir>       (run from the repository root)
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

work=${1:?usage: pure2.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")

# --- first: prove there is nothing to cut ---------------------------------
# If a menu or spell command ever acquires a real handler again, this phase is
# no longer the whole story and should say so rather than quietly do half of it.
live=$(python3 - "$f" <<'PY'
import re, sys
rows = dict((m.group(2), m.group(3)) for m in re.finditer(
    r'\[CMD_(\w+)\] = \{\(char_u \*\)"([^"]*)", sizeof\([^)]*\) - 1,\s*(\w+)\s*,',
    open(sys.argv[1], errors='surrogateescape').read()))
names = ('menu amenu nmenu vmenu imenu cmenu omenu xmenu smenu tmenu unmenu '
         'menutranslate emenu popup tunmenu tlmenu spell spellgood spellwrong '
         'spellrare spellundo spelldump spellinfo spellrepall mkspell').split()
print(' '.join(n for n in names if rows.get(n, 'ex_ni') != 'ex_ni'))
PY
)
if [ -n "$live" ]; then
    echo "  commands     still implemented, so this phase is incomplete: $live"
    exit 1
fi
echo "  commands     all 24 menu and spell commands are already ex_ni"

# --- cut the settings, and let the sweep find the rest --------------------
python3 tools/dropoptions.py "$f" \
    spell spellcapcheck spellfile spelllang spelloptions spellsuggest menuitems

tools/sweep.sh "$f"

tools/canon.sh "$f"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# --- the delta: nothing NEW, which is the claim ---------------------------
# The declared list is CUMULATIVE, measured against slim-vim's own recorded
# baselines rather than against the previous pure phase.  That is the composable
# form: each phase states the whole difference from slim, so the list can only
# grow and a phase that quietly undid an earlier one would show up.
#
# This phase adds nothing to it.  Every command here was already ex_ni, so the
# Ex sweep records nothing new; what changed is `:set`, which the sweep does not
# exercise.  The evidence that work happened is the score, not the delta, and
# saying so is better than inventing a delta to point at.
tools/puredelta.sh "$work/pure-vim" "$f" helpclose
