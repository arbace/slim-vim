#!/bin/sh
# Whim phase 36 -- the completion keys stop being keys.  See WHIM-GOAL.md.
#
# Usage: tools/whim36.sh <work-dir>      (run from the repository root)
#
# Phase 35 stubbed the five predicates completion is ENTERED through, so
# completion produces nothing, and said plainly that it stopped there: the
# `docomplete:` label and its sixteen gotos stayed, because unpicking them out
# of a 900-line switch was a larger change than that phase was making.
#
# This is that change.  Seventy functions survived Phase 35 -- reachable, so no
# sweep could touch them, and never entered, because ins_complete() returns FAIL
# before any of them runs.  A stub answers a question; it does not remove the
# caller that asks it.  So this phase removes the callers: the CTRL-X submode,
# the per-key completion arm, 'autocomplete', the four arrow-key arms, and the
# label itself.
#
# THE DELTA: none the harness records.  These are insert-mode keys, so no Ex
# command moves and no option goes.  The phase checks both halves itself, in a
# pty: completion must still be absent, and the arrow keys -- whose pum arms
# this cut -- must still move the cursor.
set -eu

work=${1:?usage: whim36.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the callers, not the callees --------------------------------------
python3 tools/nocomplkeys.py "$f"

tools/sweep.sh "$f"

# WORD-ANCHORED, for the reason phase 35 records: these names nest.
# `ins_compl_col` is a prefix of `ins_compl_col_range_attr`, which this phase
# KEEPS as a stub, so a substring count says the cut failed when it did not.
for g in docomplete ctrl_x_mode ins_complete ins_compl_addleader ins_compl_bs \
         compl_busy compl_match_array ins_compl_show_pum ins_compl_build_pum \
         ins_compl_has_autocomplete; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  complkeys    $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  complkeys    no CTRL-X mode, no match list, no menu, no docomplete"

# The last-character save lives one line away from an arm this phase cuts, and
# the first version of the tool took it instead: `lastc = c` is guarded by the
# same condition as the autocomplete disarm, three times over in edit().  It
# compiled, it swept clean, and nothing downstream objected.
if [ "$(grep -cE '^\s*lastc = c;' "$f")" != 1 ]; then
    echo "  complkeys    the lastc save is gone -- the disarm cut took the wrong block"
    exit 1
fi
echo "  complkeys    the lastc save is untouched"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/whim-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# Both halves, in a pty, because only the pair is a check.  Completion must
# still be absent -- and the arrow keys, whose `if (pum_visible())` arms this
# phase cut, must still move the cursor.  Cutting a guard and the key's real
# body together is the mistake no completion check would notice.
if python3 tools/complcheck.py "$work/whim-vim"; then
    echo "  complkeys    insert mode still inserts; CTRL-X CTRL-N completes nothing"
else
    echo "  complkeys    insert mode or CTRL-X CTRL-N is not behaving as declared"
    exit 1
fi
if ! python3 tools/arrowcheck.py "$work/whim-vim"; then
    echo "  complkeys    the arrow keys lost their insert-mode motion"
    exit 1
fi

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear
