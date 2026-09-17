#!/bin/sh
# Whim phase 68, the check -- one window, structurally.
# See pipes/whim68-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim68-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim68-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim68-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim68-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in win_split_ins win_alloc_popup_win win_init_popup_win aucmd_win AUCMD_WIN_COUNT aucmdwin_T \
         use_aucmd_win_idx win_close close_windows win_close_othertab close_last_window_tabpage \
         close_tabpage free_tabpage winframe_remove win_equal win_equal_rec frame2win win_altframe \
         make_snapshot restore_snapshot clear_snapshot clear_snapshot_rec; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  onewindow    $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
# What one window still needs: its geometry, and the status line 'laststatus' asks for.
# last_status_rec STAYS: last_status() calls it and did_set_laststatus() calls that,
# so :set laststatus still decides whether the one window gets a status line.  It was
# in the must-go list by mistake, which the header of this phase already contradicted.
for g in win_comp_pos frame_comp_pos shell_new_rows did_set_laststatus last_status last_status_rec topframe curwin firstwin win_alloc_firstwin; do
    grep -qE "\\b$g\\b" "$f" || { echo "  onewindow    $g went too -- the one window still needs it"; exit 1; }
done
echo "  onewindow    nothing can add a window or a tabpage; the one window keeps its geometry"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
printf 'alpha\nbeta\ngamma\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+2' '+normal! dd' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'alpha|gamma|' ] || { echo "  onewindow    editing broke: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }
# :q still leaves, and with a modified buffer still refuses
printf 'one\n' > "$d/q.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+normal! ix' '+q' '+wq' q.txt </dev/null >/dev/null 2>&1) || true
grep -q '^xone$' "$d/q.txt" || { echo "  onewindow    :q on a modified buffer did not refuse"; exit 1; }
# the geometry paths the frame code still serves
(cd "$d" && HOME="$d" ./vim -e -s '+set laststatus=2' '+set lines=30 columns=90' '+wq' t.txt </dev/null >/dev/null 2>&1) \
    || { echo "  onewindow    :set laststatus/lines/columns broke"; exit 1; }
echo "  onewindow    editing works; :q refuses a modified buffer; laststatus and a resize still compute"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd,retab,sort_u,sort_n,ff_dos,binary_mode,format_gq,format_comment,open_comment \
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
    lmap lnoremap lmapclear \
    jumps clearjumps
