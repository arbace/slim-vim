#!/bin/sh
# Whim phase 62, the check -- no buffer-type, file-type, listing, jump, update-time or autowrite options.
# See pipes/whim62-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim62-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim62-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim62-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim62-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in b_p_bl b_p_bt b_p_ft p_bl p_bt p_ft p_jop jop_flags p_ut p_aw p_awa autowrite autowrite_all bt_dontwrite bt_dontwrite_msg \
         bt_nofilename bt_nofileread bt_prompt set_buflisted did_set_buftype did_set_buflisted did_set_filetype_or_syntax \
         do_filetype_autocmd b_did_filetype b_au_did_filetype CCGD_AW nofile_err \
         before_blocking trigger_cursorhold updatescript ml_sync_all scriptout did_start_blocking; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  nobufopts    $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  nobufopts    none of the seven options, the bt_ helpers or the autowrite path is left"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
(cd "$d" && HOME="$d" ./vim -e -s '+set sw=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  nobufopts    the control :set sw=3 failed"; exit 1; }
for o in buflisted buftype filetype jumpoptions updatetime autowrite autowriteall; do
    if (cd "$d" && HOME="$d" ./vim -e -s "+set $o?" '+q!' </dev/null >/dev/null 2>&1); then
        echo "  nobufopts    :set $o? was accepted"; exit 1
    fi
done
printf 'x\n' > "$d/w.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1s/x/y/' '+w' '+q!' w.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/w.txt")" = y ] || { echo "  nobufopts    :w did not write: '$(cat "$d/w.txt")'"; exit 1; }
echo "  nobufopts    :set sw works; the seven are unknown; :w still writes"

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
