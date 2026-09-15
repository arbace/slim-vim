#!/bin/sh
# Whim phase 38 -- the argument list is walked by :next and :previous alone.
# See WHIM-GOAL.md.
#
# Usage: tools/whim38.sh <work-dir>      (run from the repository root)
#
# The list stays: `vim a b c` fills it, :next and :previous move through it,
# `:next x y` replaces it, :drop sets it, and quitting still says how many files
# are left.  Every other command on it goes -- twenty-five rows:
#
#   args argglobal arglocal argadd argdelete argdedupe argedit
#   argument sargument  first sfirst rewind srewind  last slast
#   snext wnext  Next sNext sprevious wNext wprevious  all sall  argdo
#
# :Next is a row of its own, spelled apart from :previous, so :N goes with it;
# :prev still reaches :previous.  See tools/noarglist.py for what a row cannot
# remove.
#
# THE DELTA: the sixteen rows that succeeded run bare, read from the slim
# baseline.  argdo, argedit, Next, sNext, snext, sprevious, wNext, wnext and
# wprevious already failed with no argument.
set -eu

work=${1:?usage: whim38.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 tools/retire.py "$f" args argglobal arglocal argadd argdelete argdedupe \
    argedit argument sargument first sfirst rewind srewind last slast \
    snext wnext Next sNext sprevious wNext wprevious all sall argdo
python3 tools/noarglist.py "$f"

tools/sweep.sh "$f"

for g in ex_args ex_argadd ex_argdelete ex_argdedupe ex_argedit ex_argument \
         ex_last ex_wnext ex_all get_arglist_name; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  arglist      $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
for g in ex_next ex_previous do_argfile ex_rewind; do
    if ! grep -qE -- "\\b$g\\b" "$f"; then
        echo "  arglist      $g is gone, and :next, :previous or :drop needed it"
        exit 1
    fi
done
echo "  arglist      :next, :previous and :drop walk the list; nothing else does"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear colorscheme \
    abbreviate noreabbrev abclear iabbrev inoreabbrev iabclear cabbrev cnoreabbrev cabclear \
    sleep smile vim9script autocmd augroup doautocmd doautoall noautocmd sandbox filetype \
    tab tabedit tabfirst tabmove tablast tabnext tabnew tabonly tabprevious tabNext tabrewind tabs redrawtabline \
    browse confirm mode open tmap tmapclear tnoremap \
    all args argadd argdelete argdedupe argglobal arglocal argument first last rewind \
    sargument sall sfirst slast srewind
