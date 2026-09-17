#!/bin/sh
# Whim phase 32, the check -- insert completion, the popup menu, and the keys that reached them.
# See pipes/whim32-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim32-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim32-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim32-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim32-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

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

tools/phasecheck.sh "$work" "$f" "$state/symbols"

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
