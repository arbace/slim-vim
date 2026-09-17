#!/bin/sh
# Whim phase 35, the check -- no scripts, no session, no autocommands.
# See pipes/whim35-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim35-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim35-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim35-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim35-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The post-condition, after the sweeps that take them.
for g in ex_source ex_redir ex_sleep ex_smile ex_scriptencoding ex_scriptversion \
         ex_vim9script ex_autocmd ex_doautocmd ex_doautoall ex_filetype ex_setfiletype \
         do_autocmd do_doautocmd event_ignored check_ei did_set_eventignore p_ei p_lpl \
         wo_eiw check_window_scroll_resize au_has_group; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  session      $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  session      no script, session or autocommand machinery is left"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear colorscheme \
    abbreviate noreabbrev abclear iabbrev inoreabbrev iabclear cabbrev cnoreabbrev cabclear \
    sleep smile vim9script autocmd augroup doautocmd doautoall noautocmd sandbox filetype
