#!/bin/sh
# Whim phase 75, the check -- no autocommands.
# See pipes/whim75-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim75-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim75-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim75-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim75-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The dispatch layer is gone, root and branch.
for g in apply_autocmds apply_autocmds_exarg apply_autocmds_retval apply_autocmds_group \
         aucmd_prepbuf aucmd_restbuf aco_save_T aubuflocal_remove au_cleanup \
         au_remove_pat au_del_cmd event_nr2name auto_next_pat getnextac first_autopat \
         last_autopat AutoPat AutoCmd AutoPatCmd_T active_apc_list au_need_clean \
         is_autocmd_blocked \
         has_cursormovedI has_textchangedI has_textchangedP trigger_cmd_autocmd \
         ins_apply_autocmds event_tab EVENT_BUFENTER NUM_EVENTS; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  noautocmd    $g still has $n mentions"; exit 1; }
done
# block_autocmds/unblock_autocmds SURVIVE: four caller pairs outside getout --
# set_string_option_direct_in_win, u_undoredo and win_alloc -- are not autocommand
# code.  Asserting they reach zero would fail the phase on its own terms.
for g in block_autocmds unblock_autocmds; do
    grep -qE "\\b$g\\b" "$f" || { echo "  noautocmd    $g went -- it has callers that are not autocommand code"; exit 1; }
done
# ...and so `autocmd_blocked` survives with them, now WRITE-ONLY: ++ in one, -- in the
# other, and is_autocmd_blocked (its only reader) gone.  That is the can_cindent shape
# again, and it belongs to the combined write-only-counter phase, not here.  Listing
# it among the must-reach-zero names would contradict the decision above.
n=$(grep -cE -- '\bautocmd_blocked\b' "$f" || true)
[ "$n" = 3 ] || { echo "  noautocmd    autocmd_blocked has $n mentions, expected 3 (declaration and the ++/-- pair)"; exit 1; }
grep -qE '\bis_autocmd_blocked\b' "$f" && { echo "  noautocmd    autocmd_blocked still has a reader"; exit 1; }
# close_buffer's abort ARM survives; the LABEL does not, and that is deliberate.
# All three `goto aucmd_abort` sat in conditions that fold away, so keeping the label
# would leave it unused -- gcc says "label defined but not used", which the sweep
# does not remove.  The abort is now reached directly by `if (abort_if_last)`.
awk '/^close_buffer\(/,/^\}$/' "$f" | grep -qE 'aucmd_abort' && { echo "  noautocmd    close_buffer still has an orphaned abort label"; exit 1; }
awk '/^close_buffer\(/,/^\}$/' "$f" | grep -qE 'e_autocommands_caused_command_to_abort' || { echo "  noautocmd    close_buffer lost its abort_if_last arm"; exit 1; }
# the write path keeps the four flags the scaffolding was wrapped around
awk '/^buf_write\(/,/^\}$/' "$f" | grep -qE '\bbuf_ffname\b' || { echo "  noautocmd    buf_write lost buf_ffname -- :w on a renamed buffer would break"; exit 1; }
awk '/^buf_write\(/,/^\}$/' "$f" | grep -qE '\bbuf_fname_s\b' || { echo "  noautocmd    buf_write lost buf_fname_s"; exit 1; }
# What must survive: the real work the autocmd calls were wrapped around.
awk '/^open_buffer\(/,/^\}$/' "$f" | grep -qE 'BF_CHECK_RO \| BF_NEVERLOADED' || { echo "  noautocmd    open_buffer lost its flag clearing"; exit 1; }
for g in close_buffer buf_freeall buf_write readfile set_curbuf buflist_new open_buffer \
         ins_redraw getout do_one_cmd set_termname u_save curbufIsChanged; do
    grep -qE "\\b$g\\b" "$f" || { echo "  noautocmd    $g went -- that was never the autocommand layer"; exit 1; }
done
echo "  noautocmd    no autocommands; the work they were wrapped around is intact"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# EVERY PROBE BELOW WAS CALIBRATED AGAINST q74 AND PASSES THERE.  A :%!sort probe was
# written first and DISCARDED: `!` was retired in phase 64, so it fails on the
# baseline too and would have measured nothing.  That is the fourth probe in this run
# that could not do what it looked like it did.
printf 'a\nb\nc\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+$' '+s/^/LAST /' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'a|b|LAST c|' ] || { echo "  noautocmd    the file did not load: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }

printf 'w1\nw2\n' > "$d/w.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! A-w' '+wq' w.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/w.txt")" = 'w1-w|w2|' ] || { echo "  noautocmd    writing broke: '$(tr '\n' '|' < "$d/w.txt")'"; exit 1; }

# :w to another name -- the buf_write path whose whole announcement block was removed
printf 'x1\n' > "$d/src.txt"; rm -f "$d/dst.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+w dst.txt' '+q!' src.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/dst.txt" 2>/dev/null)" = 'x1' ] || { echo "  noautocmd    :w to another name broke: $(cat "$d/dst.txt" 2>/dev/null)"; exit 1; }

printf 'e1\n' > "$d/e1.txt"; printf 'e2\n' > "$d/e2.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+e e2.txt' '+normal! A-E' '+wq' e1.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/e1.txt")" = 'e1' ] || { echo "  noautocmd    :e wrote over the first file: $(cat "$d/e1.txt")"; exit 1; }
[ "$(cat "$d/e2.txt")" = 'e2-E' ] || { echo "  noautocmd    :e did not load the second file: $(cat "$d/e2.txt")"; exit 1; }

printf 'keep1\ndrop\nkeep2\n' > "$d/g.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+g/drop/d' '+wq' g.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/g.txt")" = 'keep1|keep2|' ] || { echo "  noautocmd    :g broke: '$(tr '\n' '|' < "$d/g.txt")'"; exit 1; }

printf 's1\ns2\n' > "$d/s.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+%s/^s/S/' '+wq' s.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/s.txt")" = 'S1|S2|' ] || { echo "  noautocmd    :s broke: '$(tr '\n' '|' < "$d/s.txt")'"; exit 1; }

printf 'm1\nm2\nm3\n' > "$d/m.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1m$' '+wq' m.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/m.txt")" = 'm2|m3|m1|' ] || { echo "  noautocmd    :m broke: '$(tr '\n' '|' < "$d/m.txt")'"; exit 1; }

# undo -- the ins_redraw blocks that folded away carried u_save calls
printf 'u1\nu2\n' > "$d/u.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! dd' '+normal! u' '+wq' u.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/u.txt")" = 'u1|u2|' ] || { echo "  noautocmd    undo broke: '$(tr '\n' '|' < "$d/u.txt")'"; exit 1; }

# insert-mode editing, which ran through ins_apply_autocmds on every change
printf 'i1\n' > "$d/i.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+normal! A-ins' '+wq' i.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/i.txt")" = 'i1-ins' ] || { echo "  noautocmd    insert-mode editing broke: $(cat "$d/i.txt")"; exit 1; }
echo "  noautocmd    loads, writes, :w name, :e, :g, :s, :m, undo and insert all work"

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
