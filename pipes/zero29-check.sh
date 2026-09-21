#!/bin/sh
# Zero phase 29, the check -- THE CASE TABLES BECOME ONE, AND IT IS THE UNION.
# See pipes/zero29-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero29-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero29-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# and `old`, that source built with the boundary's own flags.
#
# WHAT IS CLAIMED, in five parts:
#
#   THE UNION     THE STRONGEST THING THIS CHECK SAYS, and it is not a row count.  The
#                 produced `toUpper[]`/`toLower[]` are expanded over all 1,114,112
#                 codepoints and required to be EXACTLY the union of the two tables the
#                 phase was handed, in all three directions: they agree with the INPUT's
#                 vim table wherever it mapped, with the INPUT's musl table wherever IT
#                 mapped, and they map nothing that neither did.  A row count cannot say
#                 any of that, and a merge that dropped Vithkuqi would pass one.
#                 Perturbing one produced row must break it, so it is proven able to
#                 fail.
#   THE AUTHORITY the musl half is re-derived from THIS MACHINE'S libc through ctypes
#                 (muslcase's `libc()`), not read out of the table the phase
#                 deleted.  So the check does not trust the bytes phase 15 shipped
#                 either.
#   THE RULE      nothing this phase changes on the DEFAULT arm may go un-probed, and
#                 nothing it stops mapping may go un-probed either.  Both sets are
#                 COMPUTED from the two input tables -- the first is what the union adds
#                 to vim's own table, the second is what it takes away -- and every
#                 member of both must appear in the probe text.  That stays true of an
#                 input this check has never seen, where the number 1 would not.
#   THE SOURCE    musl_toUpper and musl_toLower at 0 mentions with the input at 3 each,
#                 so the assertion is one that can fail; the two wrappers still there at
#                 4 mentions and reading vim's tables; utf_convert at the same six
#                 calls; the boundary still the first of eleven #includes, and the cut
#                 compiling silently with the SAME thirteen names, read at run time.
#   SYMBOLS       `nm -u` is THE SAME SET, as a `comm` empty in both directions, and
#                 `main` is still the only external symbol.  Changing data frees no libc
#                 symbol and needs none; the eleven phase 15 freed stay freed.
#
# THE DELTA RUNS ON BOTH ARMS, and getting that wrong is the easiest mistake here.
# `utf_toupper()`/`utf_tolower()` read musl's table whenever `internal` is NOT in
# `'casemap'`, and that arm now reads the union -- so the 96 upper and 96 lower
# codepoints vim knows and musl did not ARRIVE there, and the sharp s KEEPS the mapping
# it had.  The DEFAULT arm reads vim's own table, and the one row the union adds arrives
# there: `:s/.*/\U&/` on `ß` draws `ẞ` where it drew `ß`.  Six probe sessions move and
# six do not.
#
# TWO TRAPS THE PROBES HAD TO GET RIGHT, both measured rather than reasoned.
# `gU`, `g~` and `~` CANNOT show the sharp s at all: `swapchar()` hard-codes
# U+00DF -> U+1E9E before it consults any table, so `gUU` draws `ẞ` under every
# `'casemap'` on both binaries and a probe built on it would have reported nothing.  The
# row is reachable only through `\u`/`\U` in a substitution, which goes `do_upper` ->
# `vim_toupper` -> `utf_toupper` and hits the table directly -- and THAT IS ALSO THE
# ARGUMENT FOR THE ROW: today `swapchar()` and `toUpper[]` give different answers for
# the same character, and after this phase they agree.  And the chartab the 892 startup
# calls of `towupper`/`towlower` build does NOT move, although those calls run with
# `cmp_flags` still 0 and therefore take the non-internal arm: the union equals musl's
# table at every one of 128..255, the two having disagreed below U+0100 at U+00DF alone
# and the union taking musl's answer there.
#
# AND THE RECORDED CORPUS CANNOT SEE ANY OF IT, so `pipes/zero.delta` gains no line.
# All 102 screen cases seed themselves by typing ASCII and none of them touches
# `'casemap'`; two full recordings are byte-identical.  That is zero phase 2's
# situation -- a blind harness rather than a static phase -- and a phase in it owes
# probes of its own.  These are they.

# THE BODY IS GO: tools/go/internal/check/zero29.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/enumvals.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero29-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero29-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero29 "$work" "$state"
