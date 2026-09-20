#!/bin/sh
# Zero phase 29 -- THE CASE TABLES BECOME ONE, AND IT IS THE UNION.
#
# Usage: pipes/zero29-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# `zero-vim.c` carried TWO complete Unicode simple-case maps and they did the same job.
# vim's own `toUpper[]`/`toLower[]` have been there since whim; zero phase 15 added
# musl's as `musl_toUpper[]`/`musl_toLower[]`, range-compressed into the same
# `convertStruct` shape and read by the same `utf_convert()`, so that `towupper` and
# `towlower` could leave `nm -u`.  Which of the two the editor consults is decided by
# `'casemap'`: with `internal` set it reads vim's, without it reads musl's.  A core with
# no C library has nothing to choose between, so this phase makes it ONE table -- and
# the table is the UNION.
#
# THE SURVEY THAT PROPOSED THIS SAID THE TWO "DIFFER ON 2 OF 5 PROBES", which was
# accurate about its probe set's reach and says nothing about the truth: five characters
# cannot see 193 codepoints.  Expanded over the whole of 0..0x10FFFF -- which is what
# this edit does, and what pipes/zero29-check.sh then does again from this machine's
# libc -- the two disagree at 97 upper codepoints and 96 lower, at NONE of which both
# map to different characters, and the split is lopsided:
#
#   * vim maps and musl does not, 96 upper and 96 lower: all of Vithkuqi (U+10570..,
#     U+10597..), all of Garay (U+10D50.., U+10D70..), the enclosed Latin letters
#     U+24B6..U+24CF and U+24D0..U+24E9, Glagolitic U+2C2F/U+2C5F, the recent Latin
#     Extended-D additions (U+A7C0 U+A7C1 U+A7C7 U+A7C8 ...), U+019B, U+0264, U+1C89 and
#     U+1C8A.  vim's table is simply NEWER -- it knows Unicode 14's Vithkuqi and Unicode
#     16's Garay, and musl's casemap.h predates both.
#   * musl maps and vim does not, EXACTLY ONE: U+00DF -> U+1E9E, the sharp s.
#
# So "delete musl's and use vim's" would lose the sharp s on the non-internal arm and
# "use musl's" would lose ninety-six.  Each table knew something the other did not, and
# the union is the only answer that keeps both.  IT IS COMPUTED HERE AND NOT WRITTEN
# DOWN: the edit expands both tables, refuses on a codepoint they map differently,
# requires that no existing row covers one it is about to insert -- `utf_convert()`
# binary-searches on `rangeEnd`, so a row inside another row is unreachable -- inserts a
# `{c,c,-1,offset}` row at its sorted place, and then re-expands and requires the result
# to be exactly the union, ascending and non-overlapping.
#
# THE ONE ROW IS A DELIBERATE DIVERGENCE FROM UNICODE AND THE USER TOOK IT KNOWINGLY.
# Unicode's SIMPLE uppercase of U+00DF is U+00DF; U+1E9E is musl's tailoring, and
# putting it into vim's own table changes the DEFAULT `'casemap'`, not only the vendored
# arm: `:s/.*/\U&/` on `ß` now draws `ẞ` where it drew `ß`.  What it buys is that the
# file stops contradicting itself.  `swapchar()` has hard-coded `ß -> ẞ` for `gU`, `g~`
# and `~` all along, so today the table and the keystroke give different answers for the
# same character; after this phase they agree.
#
# WHAT IT DOES, in three parts, every one of them computed:
#
#   A  the union, INSERTED INTO VIM'S ROWS, as above.
#   B  `musl_toUpper[]` and `musl_toLower[]`, deleted with the blank line above each,
#      as ONE span from the first table's head to the second's closing brace.
#   C  `musl_towupper()` and `musl_towlower()` repointed at `toUpper[]`/`toLower[]`.
#      The two three-line wrappers STAY: they are what the non-internal arm of
#      `utf_toupper()`/`utf_tolower()` calls and what the two dead `if (c >= 0x100)`
#      arms of `vim_toupper()`/`vim_tolower()` name, and deleting them is a different
#      idea.
#
# THE FORMAT IS THE FILE'S, PROVEN AND NOT ASSUMED.  Every one of the four tables is
# parsed and re-emitted before anything is changed, and the edit refuses unless the
# re-emission is byte-identical to the text it came from.  So the rows this phase writes
# are in `tools/canon.sh`'s shape by construction rather than by resemblance.
#
# THE DELTA IS REAL AND IT RUNS ON BOTH ARMS, which is the thing a reader gets wrong
# twice over.  On the NON-INTERNAL arm -- `:set casemap=` or `casemap=keepascii`, which
# read musl's table and now read the union -- 96 upper and 96 lower codepoints gain a
# mapping they never had, and the sharp s keeps the one it had.  On the DEFAULT arm,
# which reads vim's table, the single row arrives.  Six probe sessions move and six do
# not; `pipes/zero.delta` gains no line, because the recorded corpus cannot see any of
# it.
set -eu

work=${1:?usage: zero29-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero29-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).  The check needs
# the binary this phase was HANDED, to run its twelve probes on both sides.
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero29 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  casemap      the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  casemap      the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: this phase moves BOTH arms of 'casemap' and no record can see it, so the check runs twelve probes on both binaries and two built controls beside them"

# tools/phaserun.sh sweeps next, then runs pipes/zero29-check.sh.
