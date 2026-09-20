#!/bin/sh
# Zero phase 18 -- main() is demoted to vim_main().  See ZERO-GOAL.md.
#
# Usage: pipes/zero18-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# The editor's entry point stops being the program's entry point.  What was
#
#         int
#     main
#     (int argc, char **argv)
#     {
#         ...
#         return vim_main2();
#     }
#
# becomes `static int vim_main(int argc, char **argv)` with the SAME BODY, and a new
# five-line `main()` at the bottom of the file whose whole content is
# `return vim_main(argc, argv);`.  Nothing else moves.  This is ZERO-PLAN.md 4c's
# first step, and it is deliberately the ONLY thing this phase does: the host
# boundary is a sequence of small demotions and this is the one that names them.
#
# BOTH STAY IN zero-vim.c, AND THAT IS THE POINT RATHER THAN A COMPROMISE.  Two
# tools hard-code today's invariant -- tools/phasecheck.sh's `grep -v '^main$'` and
# tools/funcreach.py's `{'main'}` root -- and splitting the launcher into a second
# translation unit is what breaks both.  Measured while `exit` was being reviewed:
# ONE APPENDED LINE to tools/phasecheck.sh moves 118 implementation keys (12 whim
# stages, 82 whim edits, 12 zero units, 12 zero edits, and no slim key).  So every
# demotion that CAN be done inside one file is done inside one file, and the split
# happens once, late, when there is nothing left to do before it.
#
# `vim_main` IS static, and that is what keeps the invariant exact.  The check asserts
# `nm --extern-only --defined-only` prints `main` and nothing else, which it has for
# every zero phase; a non-static `vim_main` would be the first zero phase ever to add
# an external symbol, and it would do it for no reason -- nothing outside this file
# calls it yet.
#
# THE NAME WAS CHECKED FOR A COLLISION BEFORE IT WAS CHOSEN.  `vim_main2()` already
# exists in this file -- it is upstream's, the second half of the old main() split at
# the point where the screen is up -- and `vim_main` is a DIFFERENT identifier, not a
# prefix collision: C has no such thing.  The assertions below pin `vim_main2` at its
# two mentions and require `vim_main` to have had NONE before this phase, both as
# whole words, so the two cannot be confused by a substring grep either.
#
# THE HEAD IS A FOSSIL AND THIS PHASE RETIRES IT.  main()'s head is spelled over THREE
# lines here --
#
#         int
#     main
#     (int argc, char **argv)
#
# -- which is upstream's, where the name and the argument list were separated by an
# `#ifdef` that gave MS-Windows a different signature.  The conditional went with the
# preprocessor in slim's phase 5 and the line break stayed.  Every other function in
# this file spells its head over two lines, so `vim_main` gets the ordinary shape and
# the new `main` gets it too.  That is a real consequence, measured and not cosmetic:
# tools/funcreach.py's definition finder never matched the three-line head, so `main`
# has never been one of the definitions it counts -- its `{'main'}` root was a name
# added by hand to a set that did not contain it.  1,755 definitions become 1,757 for
# ONE new function, and the second is `main` itself, seen for the first time.
set -eu

work=${1:?usage: zero18-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero18-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).  The
# input binary is kept because the check probes the exit statuses of BOTH.
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero18 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  demote       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  demote       the input is $state/old, $(stat -c%s "$state/old") bytes -- the check probes the exit statuses of BOTH binaries, and a status is only evidence if the binary this phase was handed is required to give the same one"

# tools/phaserun.sh sweeps next, then runs pipes/zero18-check.sh.
