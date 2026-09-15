#!/bin/sh
# Whim phase 37 -- commands that do nothing, and three that do something unwanted.
# See WHIM-GOAL.md.
#
# Usage: tools/whim37.sh <work-dir>      (run from the repository root)
#
# Read one by one in the handlers:
#
#   browse confirm         modifiers whose flags went with the dialogs; each
#                          skipped its own name and ran the rest
#   tmap tnoremap tunmap   mappings for terminal-job mode, which nothing enters
#   tmapclear
#   winpos                 "not implemented" bare, and checked two numbers and
#                          did nothing with them otherwise
#   behave                 set 'selection', 'selectmode' and 'keymodel' to
#                          another editor's habits, mswin's naming the mouse
#   mode                   a screen-mode switch no terminal here has
#   open                   vi's open mode, which is :visual after a cursor move
#
# THE DELTA: the rows that succeeded run bare -- browse, confirm, mode, open,
# tmap, tmapclear and tnoremap, read from the slim baseline.  behave, tunmap and
# winpos already failed with no argument.  :highlight stays: it is how the
# colour of 'hlsearch' is set.
set -eu

work=${1:?usage: whim37.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 tools/retire.py "$f" browse confirm tmap tnoremap tunmap tmapclear \
    winpos behave mode open
python3 tools/noinert.py "$f"

tools/sweep.sh "$f"

for g in ex_behave ex_mode ex_open ex_winpos get_behave_arg \
         e_winpos_requires_two_number_arguments e_screen_mode_setting_not_supported; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  inert        $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  inert        no handler left for a command that did nothing"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear colorscheme \
    abbreviate noreabbrev abclear iabbrev inoreabbrev iabclear cabbrev cnoreabbrev cabclear \
    sleep smile vim9script autocmd augroup doautocmd doautoall noautocmd sandbox filetype \
    tab tabedit tabfirst tabmove tablast tabnext tabnew tabonly tabprevious tabNext tabrewind tabs redrawtabline \
    browse confirm mode open tmap tmapclear tnoremap
