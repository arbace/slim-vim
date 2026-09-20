#!/bin/sh
# Whim phase 54 -- no option without a variable.  See WHIM-GOAL.md.
#
# Usage: pipes/whim54-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# A row whose variable is (char_u *)NULL is an option :set accepts, reports and
# ignores: its feature was never compiled in, or went in an earlier phase.  The
# set is COMPUTED from options[] rather than listed, so a row a later upstream
# adds without a variable goes too.
#
# THE DELTA: none the harnesses record -- no case sets an option without a
# variable.  The probes check four of them are now unknown.
set -eu

work=${1:?usage: whim54-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# The variable field, not the row: a string default is often (char_u *)NULL too.
# And the spacing varies -- 'termguicolors' is (char_u*)NULL.
# And a row's flags can wrap onto a second line -- 'diffopt', 'foldmarker',
# 'guifont', 'guifontwide', 'breakindentopt' and 'undodir' -- so the flag list
# allows whitespace; a first version without it left those six behind.
names=$(tools/st.sh query whim54 "$f")
n=$(echo $names | wc -w)
[ "$n" -gt 100 ] || { echo "  novar        found only $n rows without a variable -- the pattern stopped matching"; exit 1; }
echo "  novar        $n options have no variable"
# shellcheck disable=SC2086
tools/st.sh dropoptions "$f" $names

# tools/phaserun.sh sweeps next, then runs pipes/whim54-check.sh.
