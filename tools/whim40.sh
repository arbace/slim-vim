#!/bin/sh
# Whim phase 40 -- no window sizes to set.  See WHIM-GOAL.md.
#
# Usage: tools/whim40.sh <work-dir>      (run from the repository root)
#
# With one window there is nothing for 'winheight', 'winminheight', 'winwidth',
# 'winminwidth', 'helpheight', 'splitbelow', 'splitright', 'splitkeep',
# 'equalalways', 'eadirection', 'winfixheight' or 'winfixwidth' to decide.  The
# rows go.  The frame arithmetic that aucmd_prepbuf() still runs keeps reading
# the globals, so each keeps its default as an initialiser -- see
# tools/nowinsizes.py.
#
# THE DELTA: none the Ex sweep records beyond Phase 39's -- no row is retired.
# :set of any of these names is refused now, which the probe below checks.
set -eu

work=${1:?usage: whim40.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 tools/nowinsizes.py "$f"
# Every row goes before the sweep and without --strict: the globals are read by
# live code on purpose now, and each row's callback reads its own.  orphanopts,
# in the delta below, is what proves each survivor has an initialiser.
python3 tools/dropoptions.py "$f" splitbelow splitright splitkeep equalalways \
    eadirection winheight winminheight winwidth winminwidth helpheight
python3 tools/dropoptions.py "$f" --local winfixheight winfixwidth

tools/sweep.sh "$f"

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

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

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
