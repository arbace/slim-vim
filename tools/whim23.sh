#!/bin/sh
# Whim phase 23 -- no floating-point library.  See WHIM-GOAL.md.
#
# Usage: tools/whim23.sh <work-dir>      (run from the repository root)
#
# Three calls are the whole of libm here, and they are two different questions.
#
# ceil() and floor() appear once, in the fuzzy matcher, as the two halves of
# rounding half away from zero.  C's double-to-int conversion truncates TOWARD
# ZERO, which is ceil for a negative value and floor for a positive one, so
# biasing by half in the sign's own direction and converting is the same answer
# for every input.  tools/nolibm_check.c sweeps a million values through both
# forms and requires them to agree; this phase runs it.
#
# log10() is NOT TRANSLATED, because it cannot be.  The obvious integer
# equivalent -- dividing by ten until the value drops below ten -- is not the
# same function: just below a power of ten log10() returns a double that rounds
# up to the integer, so (size_t)log10(99.999999999999986) is 2 where counting
# digits gives 1.  The equivalence check found 79 such values in a million, and
# that is what turned this phase from a translation into a removal.
#
# So the whole floating-point branch of vim_vsnprintf() goes instead, and the
# justification is that NOTHING CAN REACH IT: there is not one %f, %F, %e, %E,
# %g or %G conversion in any format string in the file, and the single
# vim_snprintf() call whose format is not a literal takes a local `char *fmt`
# that is one of two constants.  Without +eval there is no printf() either.
#
# <math.h> STAYS -- INFINITY is the fuzzy matcher's score sentinel.  Under musl
# libm is part of libc, so the link line does not change; what changes is that
# nm -u stops naming a floating-point function.
#
# THE DELTA: none.
set -eu

work=${1:?usage: whim23.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# The claim, before the cut that relies on it.  A rounding rewrite that is
# merely believed is how an off-by-one reaches a release.
chk=$(mktemp -u)
gcc -O0 -o "$chk" tools/nolibm_check.c
if ! out=$("$chk"); then
    echo "  rounding     the rewrite is NOT the same arithmetic:"
    printf '%s\n' "$out" | sed 's/^/               /'
    rm -f "$chk"
    exit 1
fi
rm -f "$chk"
echo "  rounding     $out"

# The premise of the removal -- no float conversion in any format string -- is
# checked inside nofloat.py, which refuses to cut without it.  It has to scan
# STRING LITERALS rather than raw text: `indent % get_sw_value(curbuf)` is C,
# and a terminfo capability's `%e` is an `else`, not a conversion.

# --- cut the entry points -------------------------------------------------
python3 tools/nofloat.py "$f"


tools/sweep.sh "$f"

for g in 'ceil(' 'floor(' 'log10(' 'infinity_str' 'TYPE_FLOAT' 'typename_float'; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  libm         $g still has $n mentions after the sweep"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  libm         nothing calls a floating-point function"


tools/phasecheck.sh "$work" "$f" .cache/symbols/before

for g in ceil floor log10; do
    if grep -qx -- "$g" .cache/symbols/last/undefined; then
        echo "  symbols      $g is still undefined in the object"
        exit 1
    fi
done
echo "  symbols      ceil, floor and log10 are gone from nm -u"

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
