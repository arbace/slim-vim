#!/bin/sh
# Whim phase 82 -- the system headers nothing needs, and every comment.
# See WHIM-GOAL.md.
#
# Usage: pipes/whim82-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# whim-vim.c opens with the 41 #includes slim-vim.c has, and eighty-one phases have
# taken away most of what they were for: the directory walker, the locale,
# the password file, dlopen, setjmp, the maths library, utime, uname.  The object
# now leaves 80 symbols for libc to supply, and a header that supplies none of them
# -- no function, no type, no constant -- is a dependency on the host that buys
# nothing.
#
# THE SET IS COMPUTED, NOT LISTED.  A header's name says what it is for, not what
# this file uses from it: <sys/types.h> may be the only thing declaring a type the
# code names, and musl's headers include one another, so one that looks dead can be
# carrying another.  So each #include is tried: delete it and require the compile
# to stay SILENT under the sweep's flags.  gcc 15 compiles C23, where a call to an
# undeclared function is an error and an unknown type is an error, so "silent" is
# "nothing this header provided was used".  The candidates are tried one at a time
# and in parallel, then all together; if the set fails together -- two headers each
# covering for the other -- it falls back to removing them one by one, keeping each
# removal only while the build stays silent.  ONE BY ONE FROM THE BOTTOM: tried top
# down, the first dry run dropped <string.h> and <stdlib.h>, whose declarations also
# arrive through headers further down, and kept <wchar.h>.  The general headers come
# first in the file, so walking up from the end drops the specific ones and keeps
# the ones everything else leans on.
#
# THE PROOF IS THE BINARY, BYTE FOR BYTE.  A declaration that no longer exists cannot
# change what is compiled -- but a header can also define a function-like macro that
# shadows the function (musl's <ctype.h> does, for isalpha and friends), and losing
# one of those would change code without a word from the compiler if the prototype
# still came from somewhere.  So the input and the output are both built with
# SOURCE_DATE_EPOCH pinned, from the same file name, and must be identical.  That is
# tier 1 of the verification tiers, and it makes the delta "none" a measurement.
#
# EVERY COMMENT GOES TOO: the former-file banners, the notes, and the lines earlier
# phases wrote to explain themselves.  Reasoning lives in the phase programs,
# WHIM-GOAL.md and the commit messages; whim-vim.c carries code and nothing else, and
# no phase after this one writes a comment into it.  Comments do not reach the
# binary -- nothing uses __LINE__ -- so the byte-for-byte check covers this cut too.
# A comment is found by a scanner that knows string and character literals, since
# "pack/*/start/*" and "://" are data.  A line that was only a comment is deleted; a
# comment after code is cut with the whitespace before it; a blank run the deletions
# create is collapsed.
set -eu

work=${1:?usage: whim82-edit.sh <work-dir> <state-dir>}
state=${2:?usage: whim82-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
CC_CHECK='gcc -fsyntax-only -O0 -Wall -Wextra -Wno-unused-parameter'

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT

# The input, for the binary comparison at the end.  Same file name both sides, or
# __FILE__ differs.  Built there, not here in the background: the header trials
# below end in a bare `wait`, which reaps every child, and a later `wait $pid` on a
# reaped child is status 127 -- which is how the first dry run died.
mkdir "$state/old"
cp "$f" "$state/old/whim-vim.c"

silent() {
    out=$($CC_CHECK "$1" 2>&1) || return 1
    [ -z "$out" ]
}

if ! silent "$f"; then
    echo "  includes     the input does not compile silently -- nothing to measure against"
    exit 1
fi

# The block: every #include, and they are the first directives in the file.
grep -nE '^#include <[^>]+>$' "$f" | cut -d: -f1 > "$d/lines"
total=$(wc -l < "$d/lines")
[ "$total" -gt 0 ] || { echo "  includes     no #include lines found"; exit 1; }
if grep -vE '^#include <[^>]+>$' "$f" | grep -qE '^[ \t]*#'; then
    echo "  includes     a directive other than #include is in the file"
    exit 1
fi

# One at a time, all at once.
while read -r n; do
    (sed "${n}d" "$f" > "$d/t$n.c" && if silent "$d/t$n.c"; then echo "$n"; fi; rm -f "$d/t$n.c") &
done < "$d/lines" > "$d/cand.unsorted"
wait
sort -n "$d/cand.unsorted" > "$d/cand"
echo "  includes     $(wc -l < "$d/cand") of $total can go on their own"

# All together, and if not, one by one from the bottom.
drop() {
    sed "$(sed 's/$/d/' "$1" | tr '\n' ';')" "$f" > "$2"
}
drop "$d/cand" "$d/all.c"
if silent "$d/all.c"; then
    cp "$d/cand" "$d/keep"
    echo "  includes     and all of them together"
else
    : > "$d/keep"
    while read -r n; do
        cat "$d/keep" > "$d/try"
        echo "$n" >> "$d/try"
        drop "$d/try" "$d/t.c"
        if silent "$d/t.c"; then cp "$d/try" "$d/keep"; fi
    done <<EOF
$(sort -rn "$d/cand")
EOF
    sort -n "$d/keep" -o "$d/keep"
    echo "  includes     together they do not build; $(wc -l < "$d/keep") removed one by one, from the bottom"
fi
[ -s "$d/keep" ] || { echo "  includes     nothing to remove"; exit 1; }
removed=$(while read -r n; do sed -n "${n}s/^#include <\(.*\)>$/\1/p" "$f"; done < "$d/keep" | tr '\n' ' ')
drop "$d/keep" "$d/new.c"
cp "$d/new.c" "$f"
echo "$total" > "$state/total"
cp "$d/keep" "$state/keep"
echo "  includes     removed: $removed"

# --- every comment ---------------------------------------------------------
tools/st.sh edit whim82 "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim82-check.sh.
