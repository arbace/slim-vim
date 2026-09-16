#!/bin/sh
# Whim phase 39 -- one window, always.  See WHIM-GOAL.md.
#
# Usage: tools/whim39.sh <work-dir>      (run from the repository root)
#
# The window list stays, with one window in it; everything that makes, reaches,
# resizes, closes or binds a second goes.  Thirty-two rows:
#
#   split vsplit new vnew sview close only resize wincmd windo syncbind hide
#   sbuffer sbNext sball sbfirst sblast sbmodified sbnext sbprevious sbrewind
#   ball unhide sunhide
#   aboveleft leftabove belowright rightbelow topleft botright vertical horizontal
#
# plus CTRL-W, the command-line window (q:, q/, q?, CTRL-F), -o and -O, and the
# options that bind or fix windows or choose how to split.  :hide {cmd} is a
# modifier and stays.  See tools/nowindows.py for what a row cannot remove.
#
# THE DELTA: the twenty-seven rows that succeeded run bare, read from the slim
# baseline.  close, hide, sbmodified, wincmd and windo already failed.
set -eu

work=${1:?usage: whim39.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 tools/retire.py "$f" split vsplit new vnew sview close only resize wincmd \
    windo syncbind hide sbuffer sbNext sball sbfirst sblast sbmodified sbnext \
    sbprevious sbrewind ball unhide sunhide aboveleft leftabove belowright \
    rightbelow topleft botright vertical horizontal
python3 tools/nowindows.py "$f"
# These rows go BEFORE the sweep and without --strict -- each one's own callback
# reads its global (did_set_switchbuf, did_set_scrollopt, did_set_cedit,
# did_set_scrollbind), so while the row stands the reader is live.  The
# post-condition below is the check.
python3 tools/dropoptions.py "$f" switchbuf scrollopt cmdwinheight cedit
python3 tools/dropoptions.py "$f" --local scrollbind cursorbind winfixbuf

tools/sweep.sh "$f"
python3 tools/dropoptions.py "$f" --strict previewheight
python3 tools/dropoptions.py "$f" --strict --local previewwindow
tools/sweep.sh "$f"

for g in ex_splitview ex_close ex_only ex_resize ex_wincmd ex_syncbind ex_buffer_all \
         do_window nv_window win_split make_windows edit_buffers open_cmdwin \
         cmdwin_type cmdwin_win cmdwin_buf cmdwin_result cedit_key p_cedit p_cwh \
         p_sbo p_swb swb_flags swbuf_goto_win_with_buf tabpage_new \
         do_check_scrollbind do_check_cursorbind check_scrollbind \
         wo_scb wo_crb wo_wfb cmod_split postponed_split window_count window_layout; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  windows      $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  windows      nothing makes, reaches, closes or binds a second window"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

# -o and -O must now be what any unknown option is.  tools/clicheck.py still
# lists them as accepted, and runs in Phase 3 where they are; this is the check
# at the phase that removes them, in clicheck's terms.
for o in -o -O -o2; do
    out=$(cd "$work" && ./whim-vim "$o" -e -s -c 'qa!' </dev/null 2>&1) && rc=0 || rc=$?
    case "$out" in
        *"Unknown option argument"*) ;;
        *) echo "  cli          $o is not refused as unknown (exit $rc): $out"; exit 1 ;;
    esac
    [ "$rc" = 1 ] || { echo "  cli          $o exits $rc, expected 1"; exit 1; }
done
echo "  cli          -o and -O are unknown options"

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
    syncbind topleft unhide vertical vnew vsplit
