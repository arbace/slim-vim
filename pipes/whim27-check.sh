#!/bin/sh
# Whim phase 27, the check -- `[[=a=]]` stops meaning "a with any accent".
# See pipes/whim27-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim27-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim27-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim27-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim27-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in reg_equi_class get_equi_class; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  equiclass    $g still has $n mentions after the sweep"
        exit 1
    fi
done
# and the two that stay
for g in get_char_class get_coll_element; do
    if [ "$(grep -c "\b$g(" "$f" || true)" = 0 ]; then
        echo "  equiclass    $g went too -- [[:alpha:]] and [[.x.]] are different"
        exit 1
    fi
done
echo "  equiclass    [[=a=]] is gone; [[:alpha:]] and [[.x.]] are not"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# What the cut actually did, which no harness asks: [[=a=]] used to match an
# accented a and must now match the literal characters, while [[:alpha:]] must
# go on working.  Both halves, because only the pair is a check.
t=$(cd "$work" && rm -rf .eqtest && mkdir .eqtest && cd .eqtest \
    && printf 'xax\nx\303\241x\nx=x\n' > f.txt \
    && ../whim-vim -e -s -c 's/[[=a=]]/#/g' -c 'wq' f.txt </dev/null >/dev/null 2>&1
    tr '\n' ' ' < f.txt)
alpha=$(cd "$work" && cd .eqtest && printf 'a1b\n' > g.txt \
    && ../whim-vim -e -s -c 's/[[:alpha:]]/#/g' -c 'wq' g.txt </dev/null >/dev/null 2>&1
    tr '\n' ' ' < g.txt)
rm -rf "$work/.eqtest"
case $t in
    *'x#x'*) echo "  equiclass    [[=a=]] still matched an accented a"; exit 1 ;;
esac
if [ "$alpha" != "#1# " ]; then
    echo "  equiclass    [[:alpha:]] gave '$alpha', expected '#1# '"
    exit 1
fi
echo "  equiclass    [[=a=]] is literal now, and [[:alpha:]] still classifies"
