#!/bin/sh
# Zero phase 19 -- the core can no longer stop the process.  See ZERO-GOAL.md.
#
# Usage: pipes/zero19-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# `mch_exit()` ends the editor, and its last statement was `exit(r);`.  Phase 17 left
# that as the ONLY `exit()` call in the file and this phase replaces it with a call
# through a function pointer the host installs:
#
#     static void (*vim_host_exit)(int);           beside mch_exit's definition
#     vim_host_exit(r);                            mch_exit's last statement
#     vim_main(int argc, char **argv, void (*exit_fn)(int))
#         vim_host_exit = exit_fn;                 vim_main's first statement
#
# and phase 18's six-line launcher becomes twenty: a jump buffer, a status, a
# `host_exit()` that records the status and jumps, and a `main()` that lands there and
# RETURNS the status.  The editor no longer ends the process; it hands the process
# back, with a number.
#
# WHY A FUNCTION POINTER AND NOT A NON-LOCAL JUMP IN THE CORE.  Three routes end
# `mch_exit` without calling `exit`, and only this one is a thing the core can SAY:
#
#   * thread a return value up through every caller.  NOT AVAILABLE, and the reason is
#     a type: `cmdnames[].cmd_func` is `void (*)(exarg_T *)` for all 98 rows and
#     `nv_cmds[].cmd_func` is `void (*)(cmdarg_T *)` for all 194, both dispatched
#     through ONE indirect call, and `deathtrap` is `void (*)(int)` by the kernel's
#     contract.  It is not expensive; it cannot be written.
#   * a `setjmp` in the core.  It puts the mechanism in the file that is meant to stop
#     naming mechanisms, and it costs symbols -- see below.
#   * the core calls out and does not come back.  `vim_host_exit(r);` is four words of
#     C that say exactly that, the host decides HOW, and an indirect call names no
#     symbol.  ZERO-PLAN.md 4c settles it, and it is the one route whose C text
#     already says what a JVM host would have to do: an interface call whose
#     implementation throws.
#
# THE INDIRECTION IS TEMPORARY AND ZERO-PLAN.md 4c SAYS SO.  It exists because
# everything is still one translation unit and "nothing is global but main()" is still
# the invariant: a pointer the launcher installs through a parameter adds no external
# symbol, where a `musl_exit(int)` the host defines would.  Once the file is split
# there IS a declared boundary, `vim_host_exit` becomes a plain `musl_exit(int)`
# prototype at the top of the editor file, and the parameter and the pointer both go.
#
# THE MECHANISM IN THE LAUNCHER IS `__builtin_setjmp`/`__builtin_longjmp`, AND THAT IS
# A MEASUREMENT RATHER THAN A PREFERENCE.  Returning from `main()` is what ends the
# process without naming `exit`, and getting back to `main()` from inside `deathtrap`
# needs a non-local jump.  Measured on this tree, all three spellings:
#
#     launcher jumps with          nm -u        what it costs
#     __builtin_setjmp             32 -> 31     nothing arrives; no header
#     sigsetjmp/siglongjmp         32 -> 33     +sigsetjmp +siglongjmp, +<setjmp.h>
#     setjmp/longjmp               32 -> 33     +setjmp +longjmp, +<setjmp.h>
#     the launcher calls exit(r)   32 -> 32     nothing moves; the phase achieves
#                                               nothing at all
#
# So the two library spellings are NET WORSE than not doing the phase: `exit` leaves
# and two symbols arrive in its place, plus a thirteenth `#include` in a file whose
# last phase but two removed six.  pipes/zero19-check.sh builds the `sigsetjmp` variant
# and requires `nm -u` to show exactly that, so the road not taken is a number in the
# record and not a memory.
#
# THE ONE THING `sigsetjmp` BUYS, AND THE MEASUREMENT THAT SAYS IT IS NOT NEEDED HERE.
# `siglongjmp` restores the signal mask and `__builtin_longjmp` does not, so after a
# jump out of `deathtrap` on SIGTERM the landing site still has SIGTERM blocked
# (measured: `sigismember` says 1; on SIGHUP it says 0, because `prepare_to_exit()`
# calls `mch_signal(SIGHUP, SIG_IGN)` and that unblocks it on its way past).  THAT IS
# EXACTLY THE STATE THE PROCESS ALREADY DIED IN.  Measured on the source this phase
# was handed, with the same probe immediately before `exit(r);`: SIGTERM blocked on a
# SIGTERM death, clear on a SIGHUP one -- the identical pair.  `exit()` was being
# called from inside the handler, with the handled signal blocked, and it always has
# been.  So `__builtin_longjmp` PRESERVES the mask the process ends with and
# `siglongjmp` would CHANGE it; the check asserts the pair on both binaries.
#
# A host that keeps running rather than returning is the case where the mask matters,
# and that host does not exist yet: `main()` here lands and returns, four lines later.
# When the split happens the host writes `musl_exit(int)` for itself and owns that
# question along with `sigprocmask`, which is a symbol the HOST is allowed to name.
#
# `longjmp` OUT OF A SIGNAL HANDLER IS UNDEFINED BY THE LETTER OF C11 when the signal
# interrupted a function that is not async-signal-safe, which here it always does --
# `deathtrap` already calls `out_str`, `sprintf`, `ml_close_all` and `free`, and
# upstream has always done that and got away with it because the process was about to
# die.  It is deliberate, it is measured on musl/x86-64 at -O0, and it is said here
# rather than discovered later.  The design that removes it is the signal handlers
# becoming the host's -- `sig_winch`'s `do_resize = TRUE; return;` applied to the
# deadly two -- which is a later phase with a real declared delta.
#
# THE COUNTING TRAP, AGAIN, AND IT IS WHY THE SYMBOL IS THE ASSERTION.  `\bexit\b` is
# FIVE mentions in the input and only ONE is a call: two string literals, a
# `goto exit;` and its `exit:` label in vim_regsub_both(), and `exit(r);`.  After this
# phase it is FOUR and NONE is a call -- so `assert exit at 0 mentions` fails on a
# correct phase, and `assert 'exit(' at 0` fails on `mch_exit(`, `preserve_exit(`,
# `prepare_to_exit(`, `read_error_exit(`, `getout(` and the new `vim_host_exit(` and
# `host_exit(`.  The assertion that works is `nm -u`.
set -eu

work=${1:?usage: zero19-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero19-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero19 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  hostexit     the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  hostexit     the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from -- the exit statuses and the signal mask at the moment the process ends are measured on BOTH, and the input is the only place the old exit(r) can still be instrumented"

# tools/phaserun.sh sweeps next, then runs pipes/zero19-check.sh.
