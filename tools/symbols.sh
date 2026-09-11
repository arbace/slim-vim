#!/bin/sh
# The libc surface of a source file, and what it defines externally -- cached
# by content.
#
# Usage: tools/symbols.sh <file.c> <outdir>
#
# Writes <outdir>/undefined and <outdir>/external, and prints nothing.
#
# A phase asks this twice: once of its input, to report what the phase cost in
# dependencies, and once of its output, to check it.  Compiling a 152,000-line
# translation unit takes six and a half seconds, and THE INPUT OF ONE PHASE IS
# THE OUTPUT OF THE ONE BEFORE -- the same bytes, compiled twice, a phase apart.
#
# So the answer is cached under the file's own sha256, the same way tier 3 of
# the memoize is keyed: not by time, not by path, by content.  A phase's second
# question is the next phase's first, and the second time it is free.  Nothing
# can go stale, because a different file has a different key.
set -eu

src=${1:?usage: symbols.sh <file.c> <outdir>}
out=${2:?}
mkdir -p "$out"

sha=$(sha256sum "$src" | cut -c1-32)
cache=.cache/symbols
mkdir -p "$cache"

if [ -f "$cache/$sha.u" ] && [ -f "$cache/$sha.d" ]; then
    cp "$cache/$sha.u" "$out/undefined"
    cp "$cache/$sha.d" "$out/external"
    exit 0
fi

obj=$out/.symbols.o
gcc -c -O0 -o "$obj" "$src" 2>/dev/null
nm -u "$obj" | awk '{print $2}' | sort > "$out/undefined"
nm --extern-only --defined-only "$obj" | awk '{print $NF}' | sort > "$out/external"
rm -f "$obj"

cp "$out/undefined" "$cache/$sha.u"
cp "$out/external" "$cache/$sha.d"
