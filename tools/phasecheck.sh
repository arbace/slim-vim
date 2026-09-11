#!/bin/sh
# One compile, and everything a phase wants to know from it.
#
# Usage: tools/phasecheck.sh <work-dir> <source> <before-dir>
#
# A phase used to run gcc over its output three times: once to ask what it
# warned about, once to produce an object for the `nm` linkage check, and once
# more at the start of the NEXT phase to count the libc symbols of the very
# same bytes.  Compiling a 152,000-line translation unit takes six and a half
# seconds, so that is twenty seconds of a phase that runs in eighty.
#
# They are all one question.  This compiles once, with the warning flags, keeps
# the object, and reads the answers off it:
#
#   * did it compile, which is asked BEFORE what it complained about -- an
#     error is not a warning, and a sweep that counts lines matching "warning:"
#     finds none in a run that failed outright;
#   * exactly one external symbol, `main`;
#   * what libc it still needs, cached by the source's sha256 so that the next
#     phase's first question is a cache hit rather than another six seconds.
#
# The content key is the same idea as tier 3 of the memoize: not time, not path,
# content.  A different file has a different key, so nothing can go stale.
set -eu

work=${1:?usage: phasecheck.sh <work-dir> <source> <before-dir>}
src=${2:?}
before=${3:?}

obj=$work/phase.o
if ! gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o "$obj" "$src" \
        2>"$work/gcc.txt"; then
    echo "  compile      FAILED -- the cut did not leave valid C"
    grep -m5 'error:' "$work/gcc.txt" | sed 's/^/               /'
    exit 1
fi

warn=$(grep 'warning:' "$work/gcc.txt" | grep -cv 'implicit-fallthrough' || true)
if [ "$warn" != 0 ]; then
    echo "  warnings     $warn besides the fall-throughs -- the sweep is not finished"
    grep 'warning:' "$work/gcc.txt" | grep -v 'implicit-fallthrough' | head -5 \
        | sed 's/^/               /'
    exit 1
fi
rm -f "$work/gcc.txt"

ext=$(nm --extern-only --defined-only "$obj" | awk '{print $NF}' | grep -v '^main$' || true)
if [ -n "$ext" ]; then
    echo "  linkage      these became external: $ext"
    echo '               a dropped static declaration is a dropped linkage'
    exit 1
fi
echo "  linkage      nm on the object still prints exactly main"

sha=$(sha256sum "$src" | cut -c1-32)
mkdir -p .cache/symbols
nm -u "$obj" | awk '{print $2}' | sort > .cache/symbols/$sha.u
nm --extern-only --defined-only "$obj" | awk '{print $NF}' | sort > .cache/symbols/$sha.d
rm -f "$obj"

# The answers go beside the cache, NOT into the work directory.  A file left in
# the work tree is a file the boundary digest counts, and the first run of this
# refactor changed twenty-one boundaries by writing three of them -- the phases
# produced identical C and disagreed anyway.  The work tree is the phase's
# output; nothing that is merely how the phase checked itself belongs in it.
out=.cache/symbols/last
mkdir -p "$out"
cp .cache/symbols/$sha.u "$out/undefined"

after=$(grep -c '' .cache/symbols/$sha.u)
if [ -f "$before/undefined" ]; then
    n_before=$(grep -c '' "$before/undefined")
    gone=$(comm -23 "$before/undefined" .cache/symbols/$sha.u | tr '\n' ' ')
    echo "  symbols      $n_before -> $after${gone:+, gone: $gone}"
    echo "$n_before" > "$out/before"
else
    echo "  symbols      $after"
    echo "$after" > "$out/before"
fi
echo "$after" > "$out/after"
rm -rf "$before"
