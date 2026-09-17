#!/bin/sh
# Whim phase 60, the check -- no suffix, case, delay, verbose-file, debug or filter-program options.
# See pipes/whim60-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim60-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim60-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim60-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim60-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in p_su match_suffix p_fic p_acl delay_pending acl_elapsed p_vfile verbose_fd verbose_open verbose_stop verbose_enter verbose_leave \
         p_debug p_fp b_p_fp p_ep b_p_ep get_equalprg did_set_verbosefile did_set_debug; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  nosixopts    $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  nosixopts    none of the seven options or their readers is left"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
(cd "$d" && HOME="$d" ./vim -e -s '+set sw=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  nosixopts    the control :set sw=3 failed"; exit 1; }
for o in suffixes fileignorecase autocompletedelay verbosefile debug formatprg equalprg; do
    if (cd "$d" && HOME="$d" ./vim -e -s "+set $o?" '+q!' </dev/null >/dev/null 2>&1); then
        echo "  nosixopts    :set $o? was accepted"; exit 1
    fi
done
printf 'aaa bbb\n' > "$d/g.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+set tw=4' '+1normal! gqq' '+wq' g.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/g.txt")" = 'aaa|bbb|' ] || { echo "  nosixopts    gqq with tw=4 left '$(tr '\n' '|' < "$d/g.txt")'"; exit 1; }
echo "  nosixopts    :set sw works; the seven are unknown; gq still formats internally"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd,retab,sort_u,sort_n,ff_dos,binary_mode \
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
    startinsert startreplace startgreplace stopinsert \
    noswapfile \
    setlocal setglobal \
    lmap lnoremap lmapclear
