#!/bin/sh
# Whim phase 32 -- insert completion, the popup menu, and the keys that reached
# them.  See WHIM-GOAL.md.
#
# Usage: tools/whim32.sh <work-dir>      (run from the repository root)
#
# CTRL-N and CTRL-P complete the word being typed, and CTRL-X opens a submenu of
# sources: the current file, 'dictionary', 'thesaurus', tags, file names,
# spelling, whole lines, the command line, a register, a user function.  Almost
# none of those still exists -- tags went in phase 10, spelling was never in a
# tiny build, 'completefunc' needs +eval, and file-name completion goes through
# the globbing phase 7 removed.
#
# TWO CUTS, AND THE SWEEP BETWEEN THEM.  First the predicates: nine functions
# completion is entered through become constants, and the sweep takes the
# sources and the display behind them.  That makes completion PRODUCE NOTHING,
# and it does not remove the state machine -- seventy functions stay reachable,
# because edit() calls them directly and the redraw layer asks pum_visible() on
# its own account.  A stub answers a question; it does not remove the caller
# that asks it.  So then the callers: the CTRL-X submode, the per-key completion
# arm, 'autocomplete', the four arrow-key arms and the docomplete label, and the
# second sweep takes the callees.
#
# This was two phases, and the second existed only because the first stopped
# short.  The sweep between the cuts is kept: tools/nocomplkeys.py counts and
# matches text in edit() as the first sweep leaves it, and a count taken over
# code about to be swept is a different count.
#
# THE DELTA: none the harness records.  No behaviour case types CTRL-N and these
# are insert-mode keys, so the phase checks both halves itself, in a pty:
# completion must be absent, and insert mode must still insert.
set -eu

work=${1:?usage: whim32.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- the predicates, and the options only completion read ------------------
python3 tools/nocompl.py "$f"
python3 tools/dropoptions.py "$f" --local \
    autocomplete complete completefunc completeopt dictionary infercase \
    pumborder pummaxwidth pumopt \
    pumheight pumwidth thesaurus

tools/sweep.sh "$f"

# --- the callers, and the buffer fields those options had ------------------
python3 tools/droplocal.py "$f" b_p_cpt b_p_cot b_p_dict b_p_tsr b_p_inf b_p_ac
python3 tools/nocomplkeys.py "$f"

tools/sweep.sh "$f"

# WORD-ANCHORED, because these names nest: `pum_redraw` is a prefix of
# `pum_redraw_in_same_position` and `ins_compl_col` of `ins_compl_col_range_attr`,
# both kept as stubs, so a substring count says the cut failed when it did not.
for g in ins_compl_get_exp pum_redraw ins_compl_next b_p_cpt b_p_dict p_pumheight \
         docomplete ctrl_x_mode ins_complete ins_compl_addleader ins_compl_bs \
         compl_busy compl_match_array ins_compl_show_pum ins_compl_build_pum \
         ins_compl_has_autocomplete; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  compl        $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  compl        no sources, no match list, no menu, no CTRL-X mode, no docomplete"

# The last-character save lives one line away from an arm this phase cuts, and
# the first version of the tool took it instead: `lastc = c` is guarded by the
# same condition as the autocomplete disarm, three times over in edit().  It
# compiled, it swept clean, and nothing downstream objected.
if [ "$(grep -cE '^\s*lastc = c;' "$f")" != 1 ]; then
    echo "  compl        the lastc save is gone -- the disarm cut took the wrong block"
    exit 1
fi
echo "  compl        the lastc save is untouched"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

# Both halves, in a pty, because only the pair is a check.  Completion must be
# absent, and insert mode must still insert -- a completion check that only
# proves completion is gone also passes on a binary that cannot type.
own_checks() {
    if python3 tools/complcheck.py "$work/whim-vim"; then
        echo "  compl        insert mode still inserts; CTRL-X CTRL-N completes nothing"
    else
        echo "  compl        insert mode or CTRL-X CTRL-N is not behaving as declared"
        return 1
    fi
}
# The phase's own check needs only the binary, and so does the delta: they run
# side by side, and this one's verdict is read after the delta has finished.
checks=$(mktemp)
trap 'rm -f "$checks"' EXIT
own_checks > "$checks" 2>&1 &
pid_checks=$!

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear

if wait $pid_checks; then cat "$checks"; else cat "$checks"; exit 1; fi
