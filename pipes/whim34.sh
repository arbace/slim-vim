#!/bin/sh
# Whim phase 34 -- no abbreviations.  See WHIM-GOAL.md.
#
# Usage: pipes/whim34.sh <work-dir>      (run from the repository root)
#
# An abbreviation is a word the editor rewrites as you type it.  Nothing reads a
# vimrc here, so the only way to get one was to type :abbreviate in the session
# that wanted it; the twelve rows that did that go to ex_ni, and
# tools/noabbr.py removes the questions insert mode and the command line kept
# asking about abbreviations that can no longer exist.  The sweep takes the
# rest: check_abbr() and its wrappers, ex_abbreviate and ex_abclear.
#
# THE DELTA: the nine rows that succeeded run bare -- :abbreviate, :noreabbrev
# and :abclear, with their `i` and `c` forms, which listed or cleared nothing
# and exited 0.  The three :unabbreviate rows already failed with no argument.
# No behaviour case types an abbreviation.
set -eu

work=${1:?usage: whim34.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- the rows, then the questions ------------------------------------------
python3 tools/retire.py "$f" abbreviate noreabbrev unabbreviate abclear \
    iabbrev inoreabbrev iunabbrev iabclear cabbrev cnoreabbrev cunabbrev cabclear
python3 tools/noabbr.py "$f"

tools/sweep.sh "$f"

# The post-condition, after the sweep that takes them.
for g in check_abbr echeck_abbr ccheck_abbr ex_abbreviate ex_abclear; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  abbr         $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  abbr         nothing defines, lists or expands an abbreviation"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear colorscheme \
    abbreviate noreabbrev abclear iabbrev inoreabbrev iabclear cabbrev cnoreabbrev cabclear
