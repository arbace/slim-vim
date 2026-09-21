#!/bin/sh
# Zero phase 19, the check -- the core can no longer stop the process.
# See pipes/zero19-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero19-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero19-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# and `old`, that source built with the boundary's own flags.
#
# WHAT IS CLAIMED is that `exit` leaves the core's undefined set and NOTHING arrives in
# its place, while every way the editor can end still ends it the same way.  Four
# things could make that false and each has a build of its own:
#
#   out      the output.  `nm -u` must lose exactly `exit` and gain nothing, and no
#            spelling of a jump -- setjmp, _setjmp, sigsetjmp, longjmp, siglongjmp --
#            may be there either.  This is the whole claim and it is one `comm`.
#   alt      THE ROAD NOT TAKEN, and the reason this phase does not look like the
#            review that proposed it.  The same output with the launcher rewritten to
#            `sigsetjmp`/`siglongjmp` out of <setjmp.h>: required to show `exit` gone
#            AND `sigsetjmp` and `siglongjmp` arrived, 33 where the output is 32 --
#            worse than not doing the phase at all.  Compiled to an object only; it is
#            a number, not a program.
#   off      the control for the status table: the output with `host_code = r;` changed
#            to `host_code = r + 1;`, ONE character, which must move ALL SIX statuses.
#            A table of six agreements proves nothing unless a wrong one is caught.
#   masks    the SIGNAL MASK at the moment the process ends, measured on the INPUT
#            immediately before `exit(r);` and on the OUTPUT immediately before
#            `return host_code;`.  The two must agree, on SIGTERM and on SIGHUP.
#
# THE MASK IS THE ONE THING `sigsetjmp` WOULD BUY AND THE MEASUREMENT IS WHY IT IS NOT
# BOUGHT.  `__builtin_longjmp` does not restore the process mask, so after a jump out
# of `deathtrap` on SIGTERM the landing site still has SIGTERM blocked.  That is
# exactly the state `exit()` was already called in -- `exit(r)` ran from inside the
# handler, with the handled signal blocked, and always did.  So the builtin PRESERVES
# what the process ends with and `siglongjmp` would CHANGE it, and the `masks` pair is
# what turns that from an argument into a number.  A host that keeps running is where
# the mask would matter, and there is none: main() lands and returns four lines later.
#
# THE COUNTING TRAP.  `exit` is FIVE words in the input and ONE is a call; FOUR in the
# output and NONE is.  `assert exit at 0 mentions` fails on a correct phase and
# `assert 'exit(' at 0` fails on mch_exit(, preserve_exit(, getout( and the new
# vim_host_exit( and host_exit(.  The assertion that works is `nm -u`, section 3.

# THE BODY IS GO: tools/go/internal/check/zero19.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/phasecheck.sh
#   tools/st.sh
set -eu

work=${1:?usage: zero19-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero19-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero19 "$work" "$state"
