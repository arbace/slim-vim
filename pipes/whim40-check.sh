#!/bin/sh
# Whim phase 40, the check -- no window sizes to set.
# See pipes/whim40-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim40-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim40-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim40-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim40-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in p_hh wo_wfh wo_wfw did_set_winheight_helpheight did_set_winminheight \
         did_set_winwidth did_set_winminwidth did_set_equalalways did_set_eadirection \
         did_set_splitkeep expand_set_eadirection expand_set_splitkeep; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  winsizes     $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  winsizes     no row, callback or field is left for a window size"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# Each name must now be refused by :set, and the control must still be taken.
probe() {
    (cd "$work" && ./whim-vim -e -s -c "set $1" -c 'qa!' </dev/null >/dev/null 2>&1)
    echo $?
}
if [ "$(probe ignorecase)" != 0 ]; then
    echo "  options      the control failed: :set ignorecase exits non-zero too"
    exit 1
fi
for o in winheight winminheight winwidth winminwidth helpheight splitbelow splitright \
         splitkeep equalalways eadirection winfixheight winfixwidth; do
    if [ "$(probe "$o?")" = 0 ]; then
        echo "  options      :set $o? was accepted, so the option is still there"
        exit 1
    fi
done
echo "  options      the twelve sizing options are refused, :set ignorecase still taken"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear colorscheme \
    abbreviate noreabbrev abclear iabbrev inoreabbrev iabclear cabbrev cnoreabbrev cabclear \
    sleep smile vim9script autocmd augroup doautocmd doautoall noautocmd sandbox filetype \
    tab tabedit tabfirst tabmove tablast tabnext tabnew tabonly tabprevious tabNext tabrewind tabs redrawtabline \
    browse confirm mode open tmap tmapclear tnoremap \
    all args argadd argdelete argdedupe argglobal arglocal argument first last rewind \
    sargument sall sfirst slast srewind \
    aboveleft ball belowright botright horizontal leftabove new only resize rightbelow \
    sbuffer sbNext sball sbfirst sblast sbnext sbprevious sbrewind split sunhide sview \
    syncbind topleft unhide vertical vnew vsplit
