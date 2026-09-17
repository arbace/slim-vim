#!/bin/sh
# Zero phase 0 -- seed, prove the copy is a copy, and record what it does.
# See ZERO-GOAL.md.
#
# Usage: pipes/zero0.sh <work-dir>       (run from the repository root)
#
# zero-vim.c begins as the committed whim-vim.c, and every later zero phase is
# measured as a delta from it.  So this phase establishes four things, in the order
# each depends on the one before:
#
#   1. the seed is whim-vim.c byte for byte (cmp);
#   2. it builds with zero's compile line, gcc -O0 -static -no-pie -s, into a binary
#      that is absolutely static: readelf -h says EXEC, there is no INTERP, no
#      dynamic section and not one relocation;
#   3. the zero baselines, .reference/zero-baselines, are what WHIM-VIM does: the
#      three harnesses whim's delta reads -- behaviour, exsweep, termcheck -- run on
#      whim-vim.c built with whim's own compile line (tools/templates/whim.mk), three
#      times, identical each time.  An existing set is compared, never overwritten;
#   4. zero-vim, built -no-pie from the identical source, shows NO difference from
#      those baselines (tools/zerodelta.sh --phase 0, with pipes/zero.delta empty), and
#      whim's own cumulative delta still holds of it against slim-vim's baselines
#      (tools/whimdelta.sh --phase <whim's last>), unchanged.
#
# Recording baselines from the pipeline's INPUT is legitimate where recording them
# from its current binary is not: whim-vim.c is immutable to this pipeline, and a
# baseline taken from it cannot agree with a later zero phase by construction.  The
# fourth step is what shows the recording describes whim-vim and not the flag.
#
# A tier 3 hit on this phase records nothing, because the phase does not run.  A
# checkout that has the cache and not .reference/zero-baselines gets them back with
# `rm -rf .cache/r0 && make zero-phase-0`.
set -eu

work=${1:?usage: zero0.sh <work-dir>}
f="$work/zero-vim.c"
base=.reference/zero-baselines

# --- 1. the seed -----------------------------------------------------------
if ! cmp -s "$f" whim-vim.c; then
    echo "  seed         DIFFERS from whim-vim.c -- the pipeline's input is not"
    echo "               what it claims, and every later delta would be measured"
    echo "               against the wrong file."
    exit 1
fi
echo "  seed         identical to whim-vim.c, $(grep -c '' "$f") lines"

# --- 2. the build, and what kind of file it is ------------------------------
make -C "$work" clean >/dev/null 2>&1 || true
if ! make -C "$work" >/dev/null 2>&1; then
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
bin="$work/zero-vim"
type=$(readelf -h "$bin" | awk -F: '$1 ~ /^ *Type$/ { sub(/^ +/, "", $2); split($2, t, " "); print t[1] }')
interp=$(readelf -l "$bin" | grep -c 'INTERP' || true)
dynamic=$(readelf -d "$bin" | grep -c '^There is no dynamic section in this file\.$' || true)
relocs=$(readelf -r "$bin" | grep -c '^There are no relocations in this file\.$' || true)
if [ "$type" != EXEC ] || [ "$interp" != 0 ] || [ "$dynamic" != 1 ] || [ "$relocs" != 1 ]; then
    echo "  static       NOT absolutely static: type $type, INTERP $interp, no-dynamic $dynamic, no-relocations $relocs"
    echo "               zero's compile line is gcc -O0 -static -no-pie -s (tools/templates/zero.mk)"
    exit 1
fi
echo "  build        ok, $(stat -c%s "$bin") bytes: EXEC, no INTERP, no dynamic section, 0 relocations"

# --- 3. the baselines, from whim-vim ---------------------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/whim"
cp whim-vim.c "$tmp/whim/whim-vim.c"
cp tools/templates/whim.mk "$tmp/whim/Makefile"
if ! make -C "$tmp/whim" >/dev/null 2>&1; then
    echo "  whim-vim     FAILED to build with whim's compile line (tools/templates/whim.mk)"
    exit 1
fi
wbin="$tmp/whim/whim-vim"
echo "  whim-vim     $(stat -c%s "$wbin") bytes, $(readelf -h "$wbin" | awk -F: '$1 ~ /^ *Type$/ { split($2, t, " "); print t[1] }'), the frozen input's binary"

# Three runs, the three harnesses of each at once, and every run must be the same
# bytes -- a nondeterministic baseline is worse than none (SLIM-GOAL.md).
for r in 1 2 3; do
    o="$tmp/run$r"
    mkdir -p "$o"
    python3 tools/behaviour.py "$wbin" "$o/behaviour" >/dev/null &
    pb=$!
    python3 tools/termcheck.py "$wbin" "$o/ref-term.txt" >/dev/null &
    pm=$!
    python3 tools/exsweep.py "$wbin" "$tmp/whim/whim-vim.c" "$o/ref-exsweep.txt" >/dev/null &
    ps=$!
    wait $pb $pm $ps
    [ -d "$o/behaviour" ] && [ -f "$o/ref-term.txt" ] && [ -f "$o/ref-exsweep.txt" ] || {
        echo "  baselines    run $r left a recording missing"
        exit 1
    }
    if [ "$r" != 1 ] && ! diff -r "$tmp/run1" "$o" >/dev/null; then
        echo "  baselines    run $r differs from run 1 -- not deterministic, not a baseline:"
        diff -rq "$tmp/run1" "$o" | head -10 | sed 's/^/                 /'
        exit 1
    fi
done
cases=$(ls "$tmp/run1/behaviour" | grep -c '')
cmds=$(grep -c '' "$tmp/run1/ref-exsweep.txt")
terms=$(grep -c '' "$tmp/run1/ref-term.txt")

if [ -d "$base" ]; then
    if ! diff -r "$base" "$tmp/run1" >/dev/null; then
        echo "  baselines    DIFFER from the recorded $base:"
        diff -rq "$base" "$tmp/run1" | head -10 | sed 's/^/                 /'
        echo "               whim-vim.c is this pipeline's immutable input, so the same"
        echo "               input recorded differently: a harness changed, or the frozen"
        echo "               whim-vim.c did.  Name which before removing $base."
        exit 1
    fi
    echo "  baselines    match $base: $cases cases, $cmds Ex commands, $terms terminals, 3 identical runs"
else
    mkdir -p .reference
    rm -rf "$base.part"
    cp -r "$tmp/run1" "$base.part"
    mv "$base.part" "$base"
    echo "  baselines    recorded $base from whim-vim: $cases cases, $cmds Ex commands, $terms terminals, 3 identical runs"
fi

# --- 4. zero-vim against them, and whim's delta against slim ----------------
tools/zerodelta.sh "$bin" "$f" --phase 0

whim_last=$(. tools/pipeline.sh whim && echo "${PHASE_LIST##* }")
if [ -d .reference/baselines/behaviour ]; then
    # Its report names every one of whim's ~490 declared commands on one line, so
    # the line is counted here rather than printed; a failure is printed whole.
    if ! tools/whimdelta.sh "$bin" "$f" --phase "$whim_last" > "$tmp/whimdelta" 2>&1; then
        cat "$tmp/whimdelta"
        echo "  whim delta   zero-vim does NOT show whim's declared delta to phase $whim_last against slim-vim's baselines"
        exit 1
    fi
    held=$(sed -n 's/^ *delta  *exactly as declared: //p' "$tmp/whimdelta")
    printf '  %-12s %s commands and %s cases moved against slim-vim'"'"'s baselines, exactly whim'"'"'s declared delta to phase %s\n' \
        "whim delta" "$(printf '%s\n' "${held%%;*}" | wc -w)" "$(printf '%s\n' "${held#*cases:}" | wc -w)" "$whim_last"
else
    echo "  whim delta   no slim baselines at .reference/baselines -- whim's delta not rechecked"
fi
