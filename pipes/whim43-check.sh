#!/bin/sh
# Whim phase 43, the check -- no -c, --cmd, -R, -m, -M or -w.
# See pipes/whim43-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim43-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim43-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim43-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim43-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in exe_pre_commands pre_commands n_pre_commands reset_modifiable; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  cmdargs      $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  cmdargs      nothing collects or runs --cmd commands"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# Each option must now be what any unknown one is: exit 1, naming itself.  The
# control is +{command}, which must still run -- it is how everything here is
# driven now.
run() {
    out=$(cd "$work" && ./whim-vim "$@" </dev/null 2>&1) && rc=0 || rc=$?
}
run -e -s '+q!'
if [ "$rc" != 0 ]; then
    echo "  cli          the control failed: +q! exits $rc"
    exit 1
fi
for o in "-c qa!" "-cqa!" "--cmd qa!" -R -m -M -w7; do
    # shellcheck disable=SC2086
    run $o -e -s '+q!'
    case "$out" in
        *"Unknown option argument"*) ;;
        *) echo "  cli          $o is not refused as unknown (exit $rc): $out"; exit 1 ;;
    esac
    [ "$rc" = 1 ] || { echo "  cli          $o exits $rc, expected 1"; exit 1; }
done
echo "  cli          -c, --cmd, -R, -m, -M and -w are unknown; +{command} still runs"

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
