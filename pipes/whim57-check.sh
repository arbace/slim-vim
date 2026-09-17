#!/bin/sh
# Whim phase 57, the check -- no lisp.
# See pipes/whim57-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim57-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim57-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim57-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim57-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in b_p_lisp p_lisp b_p_lw p_lispwords get_lisp_indent lisp_match use_indentexpr_for_lisp did_set_lisp lispcomm CPO_LISP BV_LISP BV_LW; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  nolisp       $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  nolisp       no lisp option, indenter, word list or match mode is left"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
(cd "$d" && HOME="$d" ./vim -e -s '+set sw=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  nolisp       the control :set sw=3 failed"; exit 1; }
for o in lisp lispwords; do
    if (cd "$d" && HOME="$d" ./vim -e -s "+set $o?" '+q!' </dev/null >/dev/null 2>&1); then
        echo "  nolisp       :set $o? was accepted"; exit 1
    fi
done
# % across a ';': lisp mode stopped there, and nothing else does.
printf '(a ; b)\n' > "$d/m.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1normal! 0%x' '+wq' m.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/m.txt")" = '(a ; b' ] || { echo "  nolisp       % across ';' left '$(cat "$d/m.txt")'"; exit 1; }
echo "  nolisp       :set sw works; lisp and lispwords are unknown; % matches across ';'"
