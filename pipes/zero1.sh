#!/bin/sh
# Zero phase 1 -- the stack protector goes.  See ZERO-GOAL.md.
#
# Usage: pipes/zero1.sh <work-dir>       (run from the repository root)
#
# gcc here enables -fstack-protector-strong by default, so every function with a
# local array or an address-taken local gets a canary, and the object calls
# __stack_chk_fail -- a symbol the core needs from libc for nothing the editor
# does.  This phase adds -fno-stack-protector to the CFLAGS of the boundary's
# Makefile, and changes nothing else: zero-vim.c is not touched.
#
# The flag lives in zero/Makefile, the boundary, and not in tools/templates/zero.mk,
# which is this pipeline's INPUT: editing the template would move the input digest
# and invalidate phase 0's recording.  The root product rule states the same flags
# once, as ZEROCFLAGS in zero.mk, and `make zero-pass` refuses when they disagree
# with the makefile the last phase left.
#
# One whole program, like phase 0: there is no source edit, so nothing for a sweep
# to do, and a split phase would pay one for nothing.  Five things, in order:
#
#   1. the makefile's CFLAGS line is exactly one, and lacks the flag; it gets it;
#   2. the old CFLAGS DO reference __stack_chk_fail and the new ones do NOT --
#      nm -u on unstripped objects of the same source, both measured, so the check
#      is one that can fail;
#   3. zero-vim.c is byte for byte what the phase was handed;
#   4. it builds, still absolutely static: EXEC, no INTERP, no dynamic section,
#      no relocation;
#   5. tools/zerodelta.sh --phase 1: no behaviour case, Ex command or terminal
#      moved against whim-vim's baselines.
set -eu

work=${1:?usage: zero1.sh <work-dir>}
f="$work/zero-vim.c"
mk="$work/Makefile"
flag=-fno-stack-protector

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
sha_in=$(sha256sum "$f" | cut -c1-64)

# --- 1. the flag -------------------------------------------------------------
n=$(grep -c '^CFLAGS  *= ' "$mk" || true)
if [ "$n" != 1 ]; then
    echo "  makefile     $n CFLAGS lines in $mk, expected exactly 1"
    exit 1
fi
old=$(sed -n 's/^CFLAGS  *= *//p' "$mk")
case " $old " in *" $flag "*)
    echo "  makefile     CFLAGS already carries $flag: this phase was handed the wrong tree"
    exit 1 ;;
esac
sed -i "s/^\(CFLAGS  *= *\)\(.*\)\$/\1\2 $flag/" "$mk"
new=$(sed -n 's/^CFLAGS  *= *//p' "$mk")
if [ "$new" != "$old $flag" ]; then
    echo "  makefile     CFLAGS is '$new' after the edit, expected '$old $flag'"
    exit 1
fi
echo "  makefile     CFLAGS $old -> $new"

# --- 2. what each set of flags needs from the world ------------------------------
# shellcheck disable=SC2086
gcc -c $old -o "$tmp/old.o" "$f" 2>/dev/null &
po=$!
# shellcheck disable=SC2086
gcc -c $new -o "$tmp/new.o" "$f" 2>/dev/null &
pn=$!
wait $po && wait $pn || { echo "  objects      FAILED to compile $f with '$old' or '$new'"; exit 1; }
nm -u "$tmp/old.o" | awk '{print $NF}' | sort -u > "$tmp/old.u"
nm -u "$tmp/new.o" | awk '{print $NF}' | sort -u > "$tmp/new.u"
if ! grep -qx __stack_chk_fail "$tmp/old.u"; then
    echo "  symbols      the old CFLAGS do not reference __stack_chk_fail -- the check below"
    echo "               could not fail, so it proves nothing.  Has the compiler's default changed?"
    exit 1
fi
if grep -qx __stack_chk_fail "$tmp/new.u"; then
    echo "  symbols      __stack_chk_fail is still undefined with '$new'"
    exit 1
fi
gone=$(comm -23 "$tmp/old.u" "$tmp/new.u" | tr '\n' ' ')
came=$(comm -13 "$tmp/old.u" "$tmp/new.u" | tr '\n' ' ')
if [ "$gone" != "__stack_chk_fail " ] || [ -n "$came" ]; then
    echo "  symbols      expected exactly __stack_chk_fail to go; gone: ${gone:-(none)}; new: ${came:-(none)}"
    exit 1
fi
echo "  symbols      $(grep -c '' "$tmp/old.u") -> $(grep -c '' "$tmp/new.u") undefined: __stack_chk_fail goes, nothing comes"

# --- 3. the source is untouched --------------------------------------------------
if [ "$(sha256sum "$f" | cut -c1-64)" != "$sha_in" ]; then
    echo "  source       zero-vim.c CHANGED -- this phase edits the makefile only"
    exit 1
fi

# --- 4. the build, and what kind of file it is ------------------------------
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
    exit 1
fi
echo "  build        ok, $(stat -c%s "$bin") bytes: EXEC, no INTERP, no dynamic section, 0 relocations"

# --- 5. behaviour ------------------------------------------------------------
tools/zerodelta.sh "$bin" "$f" --phase 1
