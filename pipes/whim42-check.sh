#!/bin/sh
# Whim phase 42, the check -- one buffer, always.
# See pipes/whim42-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim42-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim42-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim42-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim42-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in buf_hide p_hid b_p_bh setaltfname buflist_altfpos w_alt_fnum goto_buffer \
         do_buffer_ext ex_bnext ex_bprevious nv_hat did_set_bufhidden; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  onebuffer    $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
if grep -qE 'cmod_flags (&|\|=) CMOD_(KEEPALT|HIDE)\b' "$f"; then
    echo "  onebuffer    :keepalt or :hide is still set or tested after the sweep"
    grep -nE 'cmod_flags (&|\|=) CMOD_(KEEPALT|HIDE)\b' "$f" | head -3 | cut -c1-100 | sed 's/^/               /'
    exit 1
fi
# Every buffer a file name can make now goes through do_ecmd(), which wipes the
# one it leaves, or through alist_add() on the empty startup buffer, which reuses
# it.  Asked after the sweep, when a caller that could make another is gone or
# is still here to be seen.
calls=$(grep -cE '\bbuflist_new\(' "$f" || true)
echo "  onebuffer    buflist_new is named $calls times: $(grep -nE '^[ \t]+[^ \t].*\bbuflist_new\(' "$f" | wc -l) calls"
echo "  onebuffer    nothing hides, nothing is the alternate, and a buffer left is wiped"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# The one behaviour this phase exists to change, checked against what it replaces.
# A mark lives in its buffer.  Under 'nohidden' an unloaded buffer keeps its marks,
# so leaving a file and coming back finds 'a; a wiped one does not.  So: mark line
# 2, leave for another file, come back, and delete to the mark.  One buffer means
# the mark is gone and the file is unchanged.
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
printf 'one\ntwo\nthree\n' > "$d/a"
printf 'other\n' > "$d/b"
(cd "$d" && ./vim -e -s '+2' '+mark a' '+e b' '+e a' "+'ad" '+w' '+q!' a </dev/null >/dev/null 2>&1) || true
if [ "$(cat "$d/a")" != "$(printf 'one\ntwo\nthree')" ]; then
    echo "  onebuffer    a mark survived leaving its file -- the buffer was kept, not wiped"
    cat "$d/a" | sed 's/^/               /'
    exit 1
fi
(cd "$d" && ./vim -e -s '+e b' '+e #' '+q!' a </dev/null >/dev/null 2>&1) && rc=0 || rc=$?
if [ "$rc" = 0 ]; then
    echo "  onebuffer    :e # succeeded, so there is still an alternate file"
    exit 1
fi
printf 'one\n' > "$d/a"
(cd "$d" && ./vim -e -s '+saveas c' '+s/$/X/' '+w' '+q!' a </dev/null >/dev/null 2>&1) || true
if [ "$(cat "$d/a")" != one ] || [ "$(cat "$d/c" 2>/dev/null)" != oneX ]; then
    echo "  onebuffer    :saveas did not rename the buffer: a=$(cat "$d/a") c=$(cat "$d/c" 2>/dev/null)"
    exit 1
fi
echo "  onebuffer    a mark goes with its file, :e # is refused, :saveas renames"

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
    buffer bNext bdelete bfirst blast brewind buffers bwipeout files ls \
    bnext bprevious keepalt
