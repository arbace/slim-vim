#!/bin/sh
# Whim phase 36 -- one tab page, always.  See WHIM-GOAL.md.
#
# Usage: tools/whim36.sh <work-dir>      (run from the repository root)
#
# A tab page is a set of windows the editor can switch between whole.  The
# tab-page list is still the container every window lives in, so it stays with
# exactly one entry, and every way to make or reach a second goes: the fifteen
# rows, the :tab modifier, the tab branches of the handlers the tab commands
# shared, gt/gT/g<Tab>, CTRL-PageUp/PageDown, CTRL-W T/gt/gT/g<Tab>/gf, the tab
# line, and 'showtabline', 'tabline', 'tabpagemax' and 'tabclose'.  Each key keeps
# the answer it already gave with one tab page.  See tools/notabs.py.
#
# THE DELTA: the thirteen rows that succeeded run bare -- :tab, :tabedit,
# :tabfirst, :tabmove, :tablast, :tabnext, :tabnew, :tabonly, :tabprevious,
# :tabNext, :tabrewind, :tabs and :redrawtabline -- measured before the cut.
# :tabclose and :tabdo already failed with no argument.  No harness opens a tab
# page.
set -eu

work=${1:?usage: whim36.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- the rows, then what a row cannot reach ---------------------------------
python3 tools/retire.py "$f" tab tabclose tabdo tabedit tabfirst tabmove tablast \
    tabnext tabnew tabonly tabprevious tabNext tabrewind tabs redrawtabline
python3 tools/notabs.py "$f"
# 'tabclose' goes BEFORE the sweep and without --strict: its own callback,
# did_set_tabclose(), reads p_tcl, so while the row stands the reader is live and
# the sweep cannot take it.  The post-condition below is the check -- after the
# sweep nothing names p_tcl or tcl_flags.
python3 tools/dropoptions.py "$f" tabclose

tools/sweep.sh "$f"
python3 tools/dropoptions.py "$f" --strict showtabline tabline tabpagemax
tools/sweep.sh "$f"

# The post-condition, after the sweeps that take them.
for g in ex_tabclose ex_tabnext ex_tabmove ex_tabonly ex_tabs ex_redrawtabline \
         goto_tabpage goto_tabpage_lastused win_new_tabpage tabpage_close tabpage_move \
         may_open_tabpage p_stal p_tpm p_tcl tcl_flags postponed_split_tab; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  tabs         $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  tabs         nothing makes, reaches, moves, lists or draws a second tab page"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear colorscheme \
    abbreviate noreabbrev abclear iabbrev inoreabbrev iabclear cabbrev cnoreabbrev cabclear \
    sleep smile vim9script autocmd augroup doautocmd doautoall noautocmd sandbox filetype \
    tab tabedit tabfirst tabmove tablast tabnext tabnew tabonly tabprevious tabNext tabrewind tabs redrawtabline
