#!/bin/sh
# Zero phase 36 -- the core's libc prototype block empties.  ZERO-PLAN.md 4c, ZERO-GOAL.md.
#
# Usage: pipes/zero36-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# TWO LINES ARE LEFT IN THE CORE'S BLOCK OF ORDINARY DECLARATIONS AND THIS PHASE TAKES
# BOTH.  Phase 35 took `malloc`, `free` and `write`, the three the editor uses so
# constantly that nobody had looked at them, and wrote its own programs so that the phase
# which empties the block would need no further edit to the machinery:
#
#     int getpid(void);
#     int kill(int pid, int sig);
#
# THEY ARE REACHED TWO DIFFERENT WAYS AND ONLY ONE OF THEM NEEDS A HOST CALL.
#
#   getpid   IS AVOIDABLE OUTRIGHT, not moved.  `mch_get_pid()` is `return (long)getpid();`
#            and has exactly ONE caller, `long_to_char(mch_get_pid(), b0p->b0_pid)` in
#            ml_open().  `b0_pid` is the process id written into block zero of a swap
#            file, and it has exactly TWO mentions in the whole file -- its own
#            declaration and that write.  IT IS WRITE-ONLY: nothing in any build of
#            zero-vim reads it back, because the swap file it belonged to is a disk
#            format this editor has not had since the filesystem phases took every way
#            to name a file.  So the write goes, mch_get_pid() goes with it, and `getpid`
#            leaves the core without anybody calling a host.  Zero phase 20 saw this
#            coming and said so -- "`b0_pid` is written and never read, so one line frees
#            it whenever block zero is somebody's phase".  This is that phase.
#   kill     NEEDS A HOST CALL.  Its one core site is in vim_handle_signal():
#            `kill(getpid(), got_signal);`, re-raising a deadly signal that arrived while
#            the editor was not reading.  It becomes `host_raise(got_signal);`, and the
#            host defines
#
#                static void host_raise(int sig);
#
#            beside host_exit, host_message, host_time, host_alloc, host_free and
#            host_write.  IT TAKES NO PID, and that is the whole shape of it: a core that
#            can no longer ask for its own process id must not be handed one.  What the
#            core says is "raise this signal on me"; WHICH process that is, is the host's
#            idea, exactly as fd 1 is the host's idea of where the screen is
#            (host_write, phase 35) and fd 0 the host's idea of where the keyboard is
#            (musl_read_input, phase 20).
#
# THE DEFINITION GOES INSIDE THE HOST BLOCK AND NOT BELOW IT, which is phase 26's lesson
# about musl_gettimeofday and phase 28's about musl_now_ms.  `zhostonly` reads the
# host region as the lines from `host_winch_pending` to musl_suspend's last brace, and
# host_raise's body says `kill` and `getpid`; a definition below musl_suspend would put
# two host words outside the region and the tool would refuse.  So it is written
# immediately above musl_suspend, which is the last function of that region.
#
# THE NAME PASSES `zhostonly`'s PATTERN FOR THE REASON `musl_gettimeofday` DOES.
# `raise` is in that tool's vocabulary and `\braise\b` cannot match inside `host_raise`,
# because `_` is a word character -- the same trick that lets `musl_gettimeofday` sit in
# the host block while the bare `gettimeofday` is a word the core may not say.  And
# host_raise's body calls `kill(getpid(), sig)` rather than libc's `raise()`: `raise` has
# not been an undefined symbol of this file since phase 20, and a wrapper that reached
# for it would ADD a libc symbol in a phase whose whole subject is the core's last two.
#
# WHAT THIS PHASE IS FOR.  When the block is empty the core names no libc function at
# all.  The edit does not assert that -- it finds the block, takes the two lines it owns
# out of it, and prints what is left, exactly as phase 35's does; the check states the
# claim as a measurement of the OUTPUT, and computes it from `make editor.c`'s cut rather
# than from the block, because those are two different assertions and only the first is
# the claim.  A bare declaration is invisible to the cut -- gcc warns `used but never
# defined` for a `static` function and says nothing about an `extern` one -- so what the
# check measures is `nm -u` of an object of the CUT ALONE, which is the set of names the
# core needs from outside itself.
#
# THE FOLD THAT IS NOT THERE, SURVEYED AND NOT TAKEN.  Phase 17 removed deathtrap()'s
# `entered >= 3` ladder as code no build of zero-vim could reach, which leaves `entered`
# able to reach 2 and no further, and the question was put whether that makes anything
# around the `if (entered == 2)` arm foldable.  Measured, it does not: `entered` has
# exactly three reachable values and EVERY ONE OF THEM IS READ.  0 is read by the guard
# `if (entered == 0 && ...)`, which is what distinguishes the first entry from a nested
# one; 1 and 2 are told apart TWICE -- by `if (entered == 2)`, the double-signal arm
# which calls getout(1) and never returns, and by `v_dying = entered;`, whose value
# reaches getout()'s two `if (v_dying <= 1)` tests and selects the buffer cleanup there.
# So the counter is genuinely three-valued, no two of its states are interchangeable, and
# there is no fold to take.  This edit therefore leaves deathtrap() alone, and the check
# asserts that as a byte comparison of the function in and out rather than leaving it to
# be believed.
#
# THE INPUT BINARY IS BUILT HERE with SOURCE_DATE_EPOCH=0, and the check records from it.
set -eu

work=${1:?usage: zero36-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero36-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero36 "$f" "$state"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  noclib       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  noclib       the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- one call site changes from a direct libc call to a call into the host, a definition arrives and a function goes, so the binary is NOT byte-identical and the evidence is a RECORDING with probes for both halves of the phase"

# tools/phaserun.sh sweeps next, then runs pipes/zero36-check.sh.
