#!/bin/sh
# Whim phase 3, the check -- no introduction, and the command line says only what the editor still decides.
# See pipes/whim3-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim3-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim3-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim3-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim3-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The post-condition, asked after the sweep because it is the sweep that takes
# the functions: nothing the introduction or a dropped option needed is left.
for g in '\blist_version\b' '\busage\(' '\bmaybe_intro_message\b' \
         '\bcompiled_(user|sys)\b' '\bearly_arg_scan\b' '\bmake_tabpages\b' \
         '\bset_init_clean_rtp\b' \
         '\bis_not_a_term' 'More info with' '"-nb"' \
         '"(not-a-term|noplugin|startuptime|gui-dialog-file|nofork|--clean)"'; do
    n=$(grep -cE -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  cmdline      $g still has $n mentions after the sweep"
        grep -nE -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  cmdline      nothing the introduction or a dropped option needed is left"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# --- what an invocation can say ----------------------------------------------
own_checks() {
    python3 tools/clicheck.py "$work/whim-vim"
}
# The declared delta is not checked here: tools/phaserun.sh checks the stage's, once,
# after every check in the stage has passed.
own_checks
