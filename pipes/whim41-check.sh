#!/bin/sh
# Whim phase 41, the check -- the buffer list is walked by :bnext and :bprevious alone.
# See pipes/whim41-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim41-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim41-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim41-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim41-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in ex_buffer do_exbuffer buflist_list ex_bmodified ex_brewind ex_blast \
         ex_bunload do_bufdel do_buffer ex_listdo; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  buflist      $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
# The folds in do_buffer_ext() assume DOBUF_GOTO is the only action it is ever
# handed.  That is true only once the sweep has taken do_buffer() and
# do_bufdel(), so it is asked here, after it: one call, and that one.
calls=$(grep -cE '\bdo_buffer_ext\(' "$f" || true)
goto=$(grep -c 'do_buffer_ext(DOBUF_GOTO, ' "$f" || true)
if [ "$calls" != 3 ] || [ "$goto" != 1 ]; then
    echo "  buflist      do_buffer_ext has $calls mentions and $goto DOBUF_GOTO calls, expected 3 and 1"
    exit 1
fi
left=$(grep -nE '\bCMD_(buffer|bNext|badd|balt|bdelete|bfirst|blast|bmodified|brewind|buffers|files|ls|bufdo|bunload|bwipeout)\b' "$f" \
    | grep -vE '^[0-9]+:[ \t]*(\[CMD_|CMD_)' || true)
if [ -n "$left" ]; then
    echo "  buflist      a retired buffer command is still named outside the table:"
    echo "$left" | head -5 | cut -c1-120 | sed 's/^/               /'
    exit 1
fi
for g in ex_bnext ex_bprevious goto_buffer; do
    if ! grep -qE -- "\\b$g\\b" "$f"; then
        echo "  buflist      $g is gone, and :bnext or :bprevious needed it"
        exit 1
    fi
done
echo "  buflist      :bnext and :bprevious walk the list; nothing else does"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

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
    sargument sall sfirst slast srewind \
    aboveleft ball belowright botright horizontal leftabove new only resize rightbelow \
    sbuffer sbNext sball sbfirst sblast sbnext sbprevious sbrewind split sunhide sview \
    syncbind topleft unhide vertical vnew vsplit \
    buffer bNext bdelete bfirst blast brewind buffers bwipeout files ls
