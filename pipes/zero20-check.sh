#!/bin/sh
# Zero phase 20, the check -- the signals and the terminal are the host's.
# See pipes/zero20-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero20-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero20-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# and `old`, that source built with the boundary's own flags.  EVERY PROBE BELOW IS A
# PAIR, because a number from one binary is not evidence.
#
# WHAT IS CLAIMED, in three parts, and each has its own kind of check:
#
#   STRUCTURE   the core names none of the host's vocabulary.  This is the phase's
#               real content and ``zhostonly`` is the assertion: 43 words,
#               every mention inside the host block, seven named exceptions in the
#               core that are the deadly-signal message and the clock.  A count of
#               `sigaction` would say nothing about WHERE.
#   SYMBOLS     `nm -u` loses exactly `close dup isatty raise sigaddset sigismember
#               sigprocmask` and gains nothing -- ONE comm, not two, because the two
#               halves of this phase are one phase.  It does NOT lose `sigaction
#               sigemptyset kill ioctl tcgetattr tcsetattr nanosleep select`, and the
#               check requires those PRESENT: moving code from the core to the host
#               inside one translation unit frees nothing, and a check that asserted
#               them gone would be asserting the file split had happened.
#   BEHAVIOUR   the declared delta is NOTHING, so tools/zerodelta.sh proves the
#               recording did not move -- and the recording cannot see any of this
#               (no case sends a signal, resizes a window, types `gs` or reaches EOF
#               with a terminal on fd 2), so the phase owes probes.  Fifteen of them,
#               below, seven that MUST differ and eight that MUST NOT.
#
# THE PROBES THAT MATTER MOST ARE THE ONES THAT MUST NOT DIFFER, and two of them are
# the whole reason the signal phase and the terminal phase were merged:
# `sigterm_restores` and `sighup_restores` require the editor killed mid-session to
# restore the terminal to ICANON=1 ECHO=1 ISIG=1 ONLCR=1 ICRNL=1, print `Vim: Caught
# deadly signal TERM` and `Vim: Finished.`, and exit 1 -- on BOTH binaries.  A
# host-side deadly handler that simply died would leave the tty raw, and the phase
# would have shipped a regression with a promise to fix it later.
#
# `gs_interrupt` IS THE PROBE WITH ITS OWN CONTROL.  `10gs` then CTRL-C recovers in
# about 1.8 s on both binaries; the check also builds THIS PHASE'S OWN OUTPUT with the
# two `host_tty_set` calls inside `musl_delay` deleted and requires that one NOT to
# recover at all.  Without that control, "both took 1.8 s" is two numbers agreeing and
# proves nothing about the sleep mode being real.
#
# `sigint_external` IS HERE BECAUSE IT CAUGHT A REAL BUG.  With no SIGINT handler at
# all -- which is what deleting `catch_sigint` leaves -- SIG_DFL kills the editor, and
# the `gs` probe found it: the sleep mode leaves ISIG on, so CTRL-C during a `gs`
# raises SIGINT.  The host catches it and hands the core a `0x03` byte, which is what
# `fill_input_buf` already turns into `got_int`.
#
# THE COUNTING TRAPS, AND WHY THE ASSERTIONS ARE SHAPED AS THEY ARE:
#
#   * `resize_func` IS NOT AT 0.  It is `inchar_loop`'s parameter, which stays -- the
#     core passes NULL and inchar_loop tests for it.  `assert resize_func at 0` fails
#     on a correct phase.
#   * `deathtrap` GOES UP, 3 -> 4, because the host installs it twice.  A phase about
#     removing signal handling that leaves one MORE mention of a handler is exactly
#     what this phase is, and the number says so.
#   * `errno` DOES NOT MOVE, 3 -> 3.  Both its uses are host-side now and the third is
#     `#include <errno.h>`, so `<errno.h>` leaves the CORE and `__errno_location`
#     stays in `nm -u` until the split.  Said out loud rather than implied.
#   * A PTY BYTE COUNT IS NOT AN ASSERTION.  The pty probes drive a real terminal with
#     real waits, so what they assert is structural -- exit status, terminal mode,
#     what text was drawn -- and the byte counts are REPORTED.  The two places a count
#     IS the evidence are `tstp_external`, where it must differ, and `stopcont`, where
#     both must draw a whole screen.  The deterministic pipe probes
#     (tools/zstream.py) do assert exactly.

# THE BODY IS GO: tools/go/internal/check/zero20.go and tools/go/internal/check/zero20probes.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/phasecheck.sh
#   tools/st.sh
set -eu

work=${1:?usage: zero20-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero20-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero20 "$work" "$state"
