#!/bin/sh
# Whim phase 82, the check -- the system headers nothing needs, and every comment.
# See pipes/whim82-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim82-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim82-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim82-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim82-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")
CC_CHECK='gcc -fsyntax-only -O0 -Wall -Wextra -Wno-unused-parameter'

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT

silent() {
    out=$($CC_CHECK "$1" 2>&1) || return 1
    [ -z "$out" ]
}

# What the edit found: how many includes there were, and which lines it removed.
total=$(cat "$state/total")

left=$(grep -cE '^#include <' "$f")
[ "$left" = $((total - $(wc -l < "$state/keep"))) ] || { echo "  includes     $left includes left, expected $((total - $(wc -l < "$state/keep")))"; exit 1; }
silent "$f" || { echo "  includes     the result does not compile silently"; exit 1; }

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# --- tier 1: the binary is the same bytes -----------------------------------
mkdir "$d/old"
cp "$state/old/whim-vim.c" "$d/old/"
(cd "$d/old" && SOURCE_DATE_EPOCH=0 gcc -O0 -static -s -o vim whim-vim.c)
mkdir "$d/new"
cp "$f" "$d/new/whim-vim.c"
(cd "$d/new" && SOURCE_DATE_EPOCH=0 gcc -O0 -static -s -o vim whim-vim.c)
if ! cmp -s "$d/old/vim" "$d/new/vim"; then
    echo "  includes     the binary changed -- a header was doing more than declaring"
    exit 1
fi
echo "  includes     $left includes left; the binary is byte-identical ($(wc -c < "$d/new/vim") bytes)"

# --- the delta, cumulative: phase 81's, unchanged ---------------------------
REMOVED=$(sed -n "/^REMOVED='$/,/^'$/p" pipes/whim80-edit.sh | sed '1d;$d')
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
    jumps clearjumps \
    $REMOVED
