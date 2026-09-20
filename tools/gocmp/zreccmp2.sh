#!/bin/sh
# Is `slimtools zrecord` fit to REPLACE tools/zrecord.sh as the thing that
# produces the recordings every zero check is compared against?
#
# Usage: sh tools/gocmp/zreccmp2.sh        (run from the repository root)
#
# WHY THIS IS NOT AN ORDINARY TOOL COMPARISON.  A cutter that differs moves a
# boundary and `make zero-verify` says so in the same run.  A recording harness
# that differs makes every zero check fail at once, which is loud and therefore
# survivable.  The case that is neither is a recording harness that differs
# SUBTLY -- records one redraw fewer, scrubs one field more -- because then the
# recordings still look like recordings, every check still passes, and
# .reference/zero-baselines has quietly stopped meaning anything.  Forty-six
# phases rest on those files.
#
# So the bar is not "the two agree".  It is four things, and the third is the
# one that separates an instrument from a coincidence:
#
#   1  EQUIVALENCE.  On one binary, the Go recording and the Python recording
#      are byte-identical, file for file.
#
#   2  THE FROZEN BASELINE.  The Go recording of the baseline binary --
#      whim-vim.c built with whim's own compile line, which is what zero phase
#      0 records from -- reproduces .reference/zero-baselines byte for byte.
#      Those files were written by the PYTHON and have not moved since, so this
#      is a comparison against a fixed point and not against a co-moving one.
#
#   3  IT CAN STILL FAIL.  CLAUDE.md records the control: `do_addsub()`
#      returning FAIL moves exactly 11 of the 102 screen cases and nothing
#      else.  A Go recorder that agreed on everything above and then recorded
#      11 of 102 moving is an instrument; one that recorded 0 of 102 moving
#      has agreed with the Python by being blind in the same places, which no
#      amount of agreement in steps 1 and 2 would have shown.
#
#   4  DETERMINISM.  Three consecutive Go recordings of one binary are
#      identical, including the sha256 of every stdout stream -- the property
#      phase 0 and phase 3 already require of the Python.
#
# RUN IT ON AN IDLE MACHINE.  Every part of a recording drives a real pty, and
# this tree has measured pty harnesses failing 16 of 60 runs under one
# oscillating 192-way load before zpty.py learned to wait on content rather
# than on a clock.  A disagreement produced under load is not evidence of
# anything, in either direction.
set -eu

[ -d tools ] && [ -d pipes ] || { echo "zreccmp2: run me from the repository root" >&2; exit 1; }
bin=$(sh tools/gobuild.sh)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0

# The baseline binary: whim-vim.c with whim's compile line, which is what
# .reference/zero-baselines was recorded from.
echo "building the baseline binary (whim-vim.c, whim's compile line)"
SOURCE_DATE_EPOCH=0 gcc -O0 -static -s -o "$work/whim-vim" whim-vim.c

echo "1  equivalence: python vs go, same binary"
sh tools/zrecord.sh "$work/whim-vim" whim-vim.c "$work/py" >/dev/null
./"$bin" zrecord "$work/whim-vim" whim-vim.c "$work/go" >/dev/null
if diff -r "$work/py" "$work/go" > "$work/d1" 2>&1; then
    echo "   identical: $(find "$work/py" -type f | wc -l) files"
else
    echo "   DIFFER:"; head -20 "$work/d1"; fail=1
fi

echo "2  the frozen baseline: go vs .reference/zero-baselines"
if [ -d .reference/zero-baselines ]; then
    if diff -r .reference/zero-baselines "$work/go" > "$work/d2" 2>&1; then
        echo "   reproduces the recorded baselines byte for byte"
    else
        echo "   DIFFER:"; head -20 "$work/d2"; fail=1
    fi
else
    echo "   SKIPPED: no .reference/zero-baselines here"; fail=1
fi

echo "3  the instrument can still fail: do_addsub() returning FAIL"
# CLAUDE.md: this moves exactly 11 of the 102 screen cases and nothing else.
# The definition starts at a line beginning `do_addsub(` -- the file has one,
# with its own `{` on the next line -- and the forward declaration above it
# does not, ending in `;`.  Injecting after that brace makes the function a
# no-op returning FAIL, which is CTRL-A doing nothing.
awk '
    /^do_addsub\(/ { infn = 1 }
    { print }
    infn && /^\{$/ { print "    return FAIL;"; infn = 0 }
' whim-vim.c > "$work/broken.c"
if cmp -s whim-vim.c "$work/broken.c"; then
    echo "   COULD NOT BUILD THE CONTROL: do_addsub not found, so this step proves nothing"
    fail=1
else
    if SOURCE_DATE_EPOCH=0 gcc -O0 -static -s -o "$work/broken" "$work/broken.c" 2>"$work/cc.err"; then
        ./"$bin" zrecord "$work/broken" "$work/broken.c" "$work/gobroken" >/dev/null 2>&1 || true
        moved=0
        for f in "$work/go"/screen/*; do
            b=$(basename "$f")
            cmp -s "$f" "$work/gobroken/screen/$b" || moved=$((moved + 1))
        done
        echo "   $moved of 102 screen cases moved (CLAUDE.md records 11)"
        [ "$moved" -eq 11 ] || { echo "   NOT 11 -- the Go recorder does not see what the Python sees"; fail=1; }
    else
        echo "   the control did not compile:"; head -5 "$work/cc.err"; fail=1
    fi
fi

echo "4  determinism: three go recordings of one binary"
./"$bin" zrecord "$work/whim-vim" whim-vim.c "$work/g2" >/dev/null
./"$bin" zrecord "$work/whim-vim" whim-vim.c "$work/g3" >/dev/null
if diff -r "$work/go" "$work/g2" >/dev/null 2>&1 && diff -r "$work/go" "$work/g3" >/dev/null 2>&1; then
    echo "   three recordings identical"
else
    echo "   NOT DETERMINISTIC"; fail=1
fi

[ "$fail" -eq 0 ] && echo "zreccmp2: all four -- slimtools zrecord is fit to replace the shell" \
                  || echo "zreccmp2: NOT fit to replace the shell yet"
exit "$fail"
