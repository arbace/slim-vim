#!/bin/sh
# Whim phase 31, the check -- file-name modifiers.
# See pipes/whim31-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim31-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim31-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim31-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim31-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

n=$(grep -c 'modify_fname' "$f" || true)
if [ "$n" != 0 ]; then
    echo "  fnamemod     modify_fname still has $n mentions after the sweep"
    exit 1
fi
if [ "$(grep -c '\beval_vars(' "$f" || true)" = 0 ]; then
    echo "  fnamemod     eval_vars went too -- % and # are the half this keeps"
    exit 1
fi
echo "  fnamemod     no suffix language; % and # still expand"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# Both halves, because only the pair is a check: `%` must still name the file
# being edited, and `%:t` must no longer mean its tail.
t=$(cd "$work" && rm -rf .fmtest && mkdir -p .fmtest/sub && cd .fmtest \
    && printf 'one\n' > sub/f.txt \
    && ../whim-vim -e -s -c 'w! copy.txt' -c 'qa!' sub/f.txt </dev/null >/dev/null 2>&1
    ../whim-vim -e -s -c 'normal Gotwo' -c 'w! %' -c 'qa!' sub/f.txt </dev/null >/dev/null 2>&1
    printf '%s' "$(tr '\n' ' ' < sub/f.txt)")
rm -rf "$work/.fmtest"
if [ "$t" != "one two " ]; then
    echo "  fnamemod     \`:w %\` gave '$t', expected 'one two '"
    exit 1
fi
echo "  fnamemod     \`:w %\` still writes the file being edited"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear
