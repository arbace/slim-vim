#!/bin/sh
# Whim phase 28, the check -- C indenting.
# See pipes/whim28-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim28-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim28-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim28-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim28-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in get_c_indent in_cinkeys do_c_expr_indent b_p_cin b_p_cino p_cinw; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  cindent      $g still has $n mentions after the sweep"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
# and the indenters that are not this one
for g in get_lisp_indent get_indent; do
    if [ "$(grep -c "\b$g(" "$f" || true)" = 0 ]; then
        echo "  cindent      $g went too -- 'lisp' and 'autoindent' are not this"
        exit 1
    fi
done
echo "  cindent      no C syntax model; 'autoindent' and 'lisp' untouched"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# 'autoindent' must still indent, and `:set cindent` must now be refused.  The
# control is what makes the second a check rather than a tautology.
ai=$(cd "$work" && rm -rf .citest && mkdir .citest && cd .citest \
     && printf '    one\n' > f.txt \
     && ../whim-vim -e -s -c 'set autoindent' -c 'normal Gotwo' -c 'wq' f.txt \
            </dev/null >/dev/null 2>&1
     sed -n 2p f.txt | cat -A | head -1)
probe() {
    (cd "$work" && ./whim-vim -e -s -c "set $1" -c 'qa!' </dev/null >/dev/null 2>&1)
    echo $?
}
rm -rf "$work/.citest"
case $ai in
    '    two$') ;;
    *) echo "  autoindent   a new line gave '$ai', expected four spaces then two"; exit 1 ;;
esac
[ "$(probe autoindent)" = 0 ] || { echo "  options      the control failed"; exit 1; }
[ "$(probe cindent)" = 0 ] && { echo "  options      :set cindent was accepted"; exit 1; }
echo "  autoindent   still indents; :set cindent is refused"
