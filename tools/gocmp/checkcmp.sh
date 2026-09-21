#!/bin/sh
# The zero16 CHECK, shell+Python against its Go probe: same work tree, same
# state directory, same report byte for byte -- and then the same thing again
# with one line perturbed, because two programs agreeing that nothing is wrong
# is the shape this tree calls vacuous.
#
# Usage: sh tools/gocmp/checkcmp.sh            (from the repository root)
#
# WHY THIS IS NOT editcmp.sh.  An edit is a function from a tree to a tree and
# editcmp compares the tree it returns.  A check returns no tree: it reads a
# work tree, a state directory and the world, prints a report as it goes, and
# either says nothing is wrong or exits non-zero.  So what is compared here is
# the REPORT and the EXIT STATUS, and each side gets its own copy of the work
# tree -- section 5 runs `make clean` and `make` in it, and run twice in one
# directory the second side's "clean did not remove zero-vim" refusal would be
# this script's and not the phase's.
#
# THE STATE DIRECTORY IS BUILT THE WAY tools/phaserun.sh BUILDS IT and not a
# way of this script's own devising: the symbol snapshot comes from the text
# the EDIT IS HANDED (`tools/symbols.sh $f $state/symbols`, before the edit
# runs), `input-lines` is the line count of that same text, then the edit, then
# ONE sweep.  Getting that order wrong would make both sides fail identically
# and this script would still print REPORT IDENTICAL.
#
# Nothing here is part of the build.  tools/gocmp/ is named by no makefile and
# no phase program, so it enters no implementation key; the probe it runs does
# NOT have that property -- see the commit that added it.
set -eu

[ -d tools ] && [ -d pipes ] || { echo "checkcmp: run me from the repository root" >&2; exit 1; }
[ -f .build-zero/r15.tar ] || { echo "checkcmp: .build-zero/r15.tar is not here" >&2; exit 1; }

# The Go side is reached the way a phase reaches it -- tools/st.sh, which names
# tools/go/ so implhash hashes the implementation -- and NOT by building a
# private binary.  It was a private `cmd/checkprobe` while this was a probe that
# had to avoid touching the shared dispatch; now that `check` is a slimtools
# subcommand, building a second entry point would gate something no phase runs.
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
mkdir -p "$d/work" "$d/state"
tar xf .build-zero/r15.tar -C "$d/work"
f=$d/work/zero-vim.c

echo "--- the state tools/phaserun.sh would hand the check"
grep -c '' "$f" > "$d/state/input-lines"
tools/symbols.sh "$f" "$d/state/symbols"
sh pipes/zero16-edit.sh "$d/work" "$d/state" > "$d/edit.out" 2>&1 ||
    { echo "the edit refused:"; cat "$d/edit.out"; exit 1; }
tools/sweep.sh "$f" > "$d/sweep.out" 2>&1 ||
    { echo "the sweep refused:"; tail -5 "$d/sweep.out"; exit 1; }
printf '    input-lines %s, symbols %s, old %s bytes\n' \
    "$(cat "$d/state/input-lines")" \
    "$(grep -c '' "$d/state/symbols/undefined")" \
    "$(stat -c%s "$d/state/old")"

for side in py go; do
    cp -a "$d/work" "$d/$side"
    cp -a "$d/state" "$d/${side}state"
done

sh pipes/zero16-check.sh "$d/py" "$d/pystate" > "$d/py.out" 2>&1 && prc=0 || prc=$?
tools/st.sh check zero16 "$d/go" "$d/gostate" > "$d/go.out" 2>&1 && grc=0 || grc=$?

rc=0
printf '\nPASS   exit: python=%s go=%s (both must be 0)\n' "$prc" "$grc"
[ "$prc" = 0 ] && [ "$grc" = 0 ] || rc=1
if cmp -s "$d/py.out" "$d/go.out"; then
    printf '       REPORT IDENTICAL, %s lines\n' "$(grep -c '' "$d/py.out")"
else
    echo "       REPORT DIFFERS:"
    diff "$d/py.out" "$d/go.out" | head -30
    rc=1
fi

# --- THE CONTROL, and without it the above is two programs agreeing ---------
# One blank line inserted, which changes the file's length and nothing else.
# It is the smallest perturbation this check can see, and it lands in section
# 1's line-count assertion -- so section 3's thirty compiles are never reached
# and the control costs a second.  Both sides must refuse, with the same words.
# THE STATE IS COPIED FROM THE PRISTINE ONE, never from the run above:
# tools/phasecheck.sh CONSUMES $state/symbols and removes it, so a control
# seeded from a state directory that has already been checked refuses on a
# missing file and not on the perturbation.  Measured -- it did, and the two
# sides then disagreed only in how each spells "no such file", which is a
# difference between cp and Go and says nothing about the port.
for side in py go; do
    cp -a "$d/work" "$d/c$side"
    cp -a "$d/state" "$d/c${side}state"
    # awk and NOT `sed -i '200i\'`, which inserts NOTHING and makes the
    # control a second copy of the pass -- measured, it printed the whole
    # 23-line success report and this script called it a difference.
    awk 'NR == 200 { print "" } { print }' "$d/c$side/zero-vim.c" > "$d/ins" &&
        mv "$d/ins" "$d/c$side/zero-vim.c"
done
sh pipes/zero16-check.sh "$d/cpy" "$d/cpystate" > "$d/cpy.out" 2>&1 && cprc=0 || cprc=$?
tools/st.sh check zero16 "$d/cgo" "$d/cgostate" > "$d/cgo.out" 2>&1 && cgrc=0 || cgrc=$?

printf '\nCTL    exit: python=%s go=%s (both must be non-zero)\n' "$cprc" "$cgrc"
[ "$cprc" != 0 ] && [ "$cgrc" != 0 ] || rc=1
if cmp -s "$d/cpy.out" "$d/cgo.out"; then
    printf '       REPORT IDENTICAL, %s line(s):\n' "$(grep -c '' "$d/cpy.out")"
    sed 's/^/         /' "$d/cpy.out"
else
    echo "       REPORT DIFFERS:"
    diff "$d/cpy.out" "$d/cgo.out" | head -30
    rc=1
fi
exit "$rc"
