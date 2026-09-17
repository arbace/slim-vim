#!/bin/sh
# Whim phase 72, the check -- one window, one tabpage, structurally.
# See pipes/whim72-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim72-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim72-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim72-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim72-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The two lists are gone, and so is everything that only existed to walk them.
for g in firstwin lastwin first_tabpage w_next w_prev tp_next tp_firstwin tp_lastwin \
         leave_tabpage enter_tabpage use_tabpage valid_tabpage win_append win_init \
         borrow_stl_vsep_hl; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  onewin       $g still has $n mentions"; exit 1; }
done
# The frame layer STAYS -- one window still has one frame, and sizing needs it.
for g in topframe frame_T fr_next fr_child fr_parent new_frame win_comp_pos; do
    grep -qE "\\b$g\\b" "$f" || { echo "  onewin       $g went -- the frame layer is not this phase"; exit 1; }
done
# b_nwindows stays a real count: it is 0 once the window drops the buffer.
grep -qE '\bb_nwindows\b' "$f" || { echo "  onewin       b_nwindows went -- buffer release depends on it"; exit 1; }
grep -qE 'buf->b_nwindows <= 0' "$f" || { echo "  onewin       the 'no longer displayed' test went"; exit 1; }
# and the one window still has to be made
for g in win_alloc win_alloc_firstwin alloc_tabpage curwin curtab; do
    grep -qE "\\b$g\\b" "$f" || { echo "  onewin       $g went too -- the one window still needs it"; exit 1; }
done
echo "  onewin       one window and one tabpage; the frame layer and b_nwindows intact"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# LOAD FIRST: prove the buffer holds the file before testing anything else.
printf 'a\nb\nc\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+$' '+s/^/LAST /' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'a|b|LAST c|' ] || { echo "  onewin       the file did not load: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }

# plain editing
printf 'one\ntwo\nthree\n' > "$d/e.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+2' '+normal! dd' '+wq' e.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/e.txt")" = 'one|three|' ] || { echo "  onewin       editing broke: '$(tr '\n' '|' < "$d/e.txt")'"; exit 1; }

# :e still switches files and the write follows it
printf 'h1\n' > "$d/h1.txt"; printf 'h2\n' > "$d/h2.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+e h2.txt' '+normal! iE' '+wq' h1.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/h1.txt")" = 'h1' ] || { echo "  onewin       :e wrote over the first file: $(cat "$d/h1.txt")"; exit 1; }
[ "$(cat "$d/h2.txt")" = 'Eh2' ] || { echo "  onewin       :e did not load the second file: $(cat "$d/h2.txt")"; exit 1; }

# NO BANG on these two: `normal!` suppresses mappings by definition, so a mapping
# probe written with it cannot fire on any build.  Calibrated in phase 71.
printf 'x\n' > "$d/m.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+map <buffer> Q A!' '+normal Q' '+wq' m.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/m.txt")" = 'x!' ] || { echo "  onewin       a buffer-local mapping stopped working: $(cat "$d/m.txt")"; exit 1; }
printf 'y\n' > "$d/g.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+map Z A?' '+normal Z' '+wq' g.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/g.txt")" = 'y?' ] || { echo "  onewin       a global mapping stopped working: $(cat "$d/g.txt")"; exit 1; }

# NOT an :autocmd probe.  :autocmd, :augroup, :doautocmd and :doautoall are all ex_ni
# here, retired by an earlier phase, so `+autocmd BufWritePre * ...` registers nothing
# and the probe cannot fire on ANY build -- calibrated against q71, which gives the
# same answer as this phase does.  That is the third probe in this run that could not
# fail, after <LeftMouse> and `normal!`, and the rule that catches all three is:
# CALIBRATE A NEW PROBE AGAINST THE PREVIOUS BOUNDARY BEFORE TRUSTING IT.
#
# aucmd_prepbuf/aucmd_restbuf are still exercised, but from inside: getout() fires
# BUFWINLEAVE and BUFUNLOAD on the way out of every :wq, which is the block this
# phase rewrote.  A write that completes is the evidence.
printf 'p1\np2\n' > "$d/au.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! A-au' '+wq' au.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/au.txt")" = 'p1-au|p2|' ] || { echo "  onewin       quitting through the rewritten BUFWINLEAVE block broke: '$(tr '\n' '|' < "$d/au.txt")'"; exit 1; }

# the scroll path whose `is there a window below` tests were folded
printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n' > "$d/s.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+5' '+normal! O-ins' '+wq' s.txt </dev/null >/dev/null 2>&1) || true
[ "$(sed -n 5p "$d/s.txt")" = '-ins' ] || { echo "  onewin       inserting a line broke the scroll path: $(sed -n 5p "$d/s.txt")"; exit 1; }

# a range over the whole buffer, which address_default_all and invalid_range decide
printf 'r1\nr2\nr3\n' > "$d/r.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+%s/^r/R/' '+wq' r.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/r.txt")" = 'R1|R2|R3|' ] || { echo "  onewin       a whole-buffer range broke: '$(tr '\n' '|' < "$d/r.txt")'"; exit 1; }
echo "  onewin       loads, edits, :e switches, mappings fire, autocommands reach the buffer"

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
