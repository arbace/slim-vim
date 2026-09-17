#!/bin/sh
# Whim phase 33, the check -- commands whose machinery has already gone.
# See pipes/whim33-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim33-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim33-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim33-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim33-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The post-condition, asked after the sweep because it is the sweep that takes
# the handlers: nothing that existed only to refuse is left, and ex_listdo no
# longer names a quickfix command.
for g in ex_shell ex_nogui ex_digraphs ex_redrawtabpanel ex_colorscheme load_colors; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  deadcmds     $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
if python3 - "$f" <<'EOF'
import re, sys
sys.path.insert(0, 'tools')
import cutil
text = open(sys.argv[1], errors='surrogateescape').read()
a, z = cutil.find_definition(text, 'ex_listdo')
sys.exit(0 if re.search(r'\bCMD_(cdo|cfdo|ldo|lfdo)\b', text[a:z]) else 1)
EOF
then
    echo "  deadcmds     ex_listdo still tests for a quickfix command"
    exit 1
fi
echo "  deadcmds     no handler that only refused is left, and ex_listdo asks nothing about quickfix"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear colorscheme
