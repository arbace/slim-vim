#!/bin/sh
# Whim phase 39, the check -- one window, always.
# See pipes/whim39-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim39-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim39-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim39-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim39-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

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

tools/phasecheck.sh "$work" "$f" "$state/symbols"

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
