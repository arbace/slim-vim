#!/bin/sh
# Whim phase 47 -- no :startinsert, :startreplace, :startgreplace or :stopinsert.  See WHIM-GOAL.md.
#
# Usage: tools/whim47.sh <work-dir>      (run from the repository root)
#
# Commands that entered or left Insert mode from a command line: i, R, gR and
# Esc are the keys for that, and stay.
#
# THE DELTA: the four rows, which succeeded run bare.
set -eu

work=${1:?usage: whim47.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 tools/retire.py "$f" startinsert startreplace startgreplace stopinsert

tools/sweep.sh "$f"

for g in ex_startinsert ex_stopinsert; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  insertcmds   $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  insertcmds   no command enters or leaves Insert mode"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"
python3 tools/arrowcheck.py "$work/whim-vim"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd,retab,sort_u,sort_n \
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
    syncbind topleft unhide vertical vnew vsplit \
    buffer bNext bdelete bfirst blast brewind buffers bwipeout files ls \
    bnext bprevious keepalt \
    center left retab right sort uniq \
    qall quitall wall wqall xall \
    startinsert startreplace startgreplace stopinsert
