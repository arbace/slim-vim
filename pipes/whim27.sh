#!/bin/sh
# Whim phase 27 -- `[[=a=]]` stops meaning "a with any accent".  See WHIM-GOAL.md.
#
# Usage: pipes/whim27.sh <work-dir>      (run from the repository root)
#
# A POSIX bracket expression has three bracketed forms inside it, and they are
# three different features sharing a syntax:
#
#     [[:alpha:]]   a character CLASS     -- stays
#     [[.x.]]       a collating ELEMENT   -- stays
#     [[=a=]]       an equivalence CLASS  -- goes
#
# The third means "this character and every accented form of it", and expanding
# it takes reg_equi_class(), 1,397 LINES -- a switch over every base letter
# listing its variants across Latin-1 and Latin Extended-A and -B.  It is the
# largest single function left in the file, and it is reached only when a
# pattern contains `[=`.
#
# Two call sites and the sweep does the rest.  \w, \a and [[:alpha:]] are a
# different mechanism and are untouched.
#
# THE DELTA: none the harness records.  No behaviour case and no Ex command
# writes `[=` in a pattern -- which is the point.  The phase checks the change
# itself instead: `[[=a=]]` must stop matching an accented a and start matching
# the literal characters.
set -eu

work=${1:?usage: whim27.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/noequiclass.py "$f"


tools/sweep.sh "$f"

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

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

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

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
