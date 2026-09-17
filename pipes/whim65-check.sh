#!/bin/sh
# Whim phase 65, the check -- no rot13, no operator function, no empty key handler.
# See pipes/whim65-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim65-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim65-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim65-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim65-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in OP_ROT13 op_function OP_FUNCTION ins_ctrl_x e_eval_feature_not_available; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  norot13      $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
for g in swapchar op_tilde OP_TILDE OP_UPPER OP_LOWER nv_search get_op_type; do
    grep -qE "\\b$g\\b" "$f" || { echo "  norot13      $g went too -- it was not rot13's"; exit 1; }
done
# The kept-on-purpose ones, so that a later phase cannot quietly take them.
grep -qE '^[ \t]*case Ctrl_P:' "$f" || { echo "  norot13      Insert-mode CTRL-P lost its case and would insert a control character"; exit 1; }
grep -qE "\\bcase 'y':" "$f" || { echo "  norot13      zy went with the operators"; exit 1; }
echo "  norot13      no rot13, operator function or empty key handler is left"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
probe() {  # $1 = keys, $2 = expected file contents with | for newline
    printf 'abc def\nghi\n' > "$d/t.txt"
    (cd "$d" && HOME="$d" ./vim -e -s '+1' "+normal! $1" '+wq' t.txt </dev/null >/dev/null 2>&1) || true
    got=$(tr '\n' '|' < "$d/t.txt")
    [ "$got" = "$2" ] || { echo "  norot13      $1 gave '$got', expected '$2'"; exit 1; }
}
probe 'g?g?' 'abc def|ghi|'
probe 'g??'  'abc def|ghi|'
probe 'g@g@' 'abc def|ghi|'
probe 'gUU'  'ABC DEF|ghi|'
probe 'guu'  'abc def|ghi|'
probe 'g~~'  'ABC DEF|ghi|'
probe 'zyy'  'abc def|ghi|'
echo "  norot13      g? and g@ do nothing; gU, gu and g~ still change case; zy still yanks"
