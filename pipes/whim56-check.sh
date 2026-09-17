#!/bin/sh
# Whim phase 56, the check -- no shell, runtime or keyword-program options.
# See pipes/whim56-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim56-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim56-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim56-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim56-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in p_kp b_p_kp p_sh p_shq p_srr p_rtp p_pp get_isolated_shell_name csh_like_shell ExpandRTDir \
         ExpandPackAddDir expand_runtime_cmd set_context_in_runtime_cmd did_set_shellpipe_redir; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  noshellrtp   $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  noshellrtp   no shell, runtime-path or keyword-program option or reader is left"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
(cd "$d" && HOME="$d" ./vim -e -s '+set sw=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  noshellrtp   the control :set sw=3 failed"; exit 1; }
for o in shell shellquote shellredir runtimepath packpath keywordprg; do
    if (cd "$d" && HOME="$d" ./vim -e -s "+set $o?" '+q!' </dev/null >/dev/null 2>&1); then
        echo "  noshellrtp   :set $o? was accepted"; exit 1
    fi
done
echo "  noshellrtp   :set sw works; the six are unknown"

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
    setlocal setglobal
