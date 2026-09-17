#!/bin/sh
# Whim phase 30, the check -- K and the tag jumps, keeping * and #.
# See pipes/whim30-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim30-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim30-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim30-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim30-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in nv_K_getcmd do_nv_ident g_tag_at_cursor; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  ident        $g still has $n mentions after the sweep"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
# and what must remain: * and # are still in the table, and still reach nv_ident
for g in "{'*', nv_ident" "{'#', nv_ident" "{POUND, nv_ident" "{Ctrl_RSB, nv_error" "{'K', nv_error"; do
    if [ "$(grep -cF -- "$g" "$f" || true)" = 0 ]; then
        echo "  ident        $g went -- * and # are the half this phase keeps"
        exit 1
    fi
done
echo "  ident        no keywordprg and no tag jump; * # and POUND still dispatch"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# THE CHECK THIS PHASE EXISTS FOR, and it needs a pty: `normal_search()` wants a
# screen, so silent Ex mode measures something that is not the feature.  See
# tools/starcheck.py, which also records what the Ex-mode version got wrong.
own_checks() {
    if python3 tools/starcheck.py "$work/whim-vim"; then
        echo "  ident        * still finds the next whole word, and skips foobar"
    else
        echo "  ident        * no longer searches -- it is the half this phase keeps"
        return 1
    fi
}
# The declared delta is not checked here: tools/phaserun.sh checks the stage's, once,
# after every check in the stage has passed.
own_checks
