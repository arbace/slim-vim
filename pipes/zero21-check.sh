#!/bin/sh
# Zero phase 21, the check -- the messages are the editor's, the writing is the host's.
# See pipes/zero21-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero21-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero21-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# and `old`, that source built with the boundary's own flags.  EVERY PROBE BELOW IS A
# PAIR, because a number from one binary is not evidence.
#
# WHAT IS CLAIMED, in three parts:
#
#   SYMBOLS     `nm -u` loses EXACTLY `fflush fputc fputs fwrite printf putchar
#               stderr` and gains nothing -- one `comm`, never a count.  FOUR of the
#               seven are named nowhere in the source: gcc emits them from
#               `printf("%s", x)` and `fprintf(stderr, "%s", x)`.  They were predicted
#               to leave with the construct, and the empty `arrived` side is what
#               verifies the prediction.  `<stdio.h>` goes with them, 12 directives to
#               11.
#   STRUCTURE   the file has exactly TWO bare `write()` call sites -- `mch_write`'s and
#               `host_message`'s -- and one `vim_host_message` the launcher installs
#               through vim_main()'s parameter list, exactly as phase 19 installs
#               `vim_host_exit`.  `zhostonly` is run unchanged, and the phase
#               deliberately adds nothing to its VOCAB (pipes/zero21-edit.sh says why:
#               `write` would be false while mch_write holds one, and the stdio words
#               would fail phase 20's own output and so `make zero-verify` at r20).
#   BEHAVIOUR   NOTHING AT ALL.  The same bytes reach the same file descriptors at the
#               same moments; only the syscall underneath them changes.
#
# THE DECLARED DELTA IS NOTHING, AND THE FIRST CHECK OF THAT IS `diff -r` AND NOT
# tools/zerodelta.sh.  Measured on the control below: `diff -r` of the two recordings
# reports 217 lines across 24 moved records and zerodelta.sh names only FOURTEEN,
# because ten of the 24 argv rows (`-`, `--`, `-e`, `-E`, `-e -s`, `-v`, `f.txt`,
# `f.txt g.txt`, `+q! f.txt`, `-- +q!`) are already declared movers from phases 4 and 5
# and tools/zcompare.py therefore accepts any FURTHER movement in them silently.  So
# this check diffs the recording of the binary it was handed against the recording of
# the one it made, and uses zerodelta.sh as the second opinion -- on the CONTROL, where
# it must refuse.
#
# THE INSTRUMENTED PAIR IS THE EVIDENCE THAT THE DELTA IS EMPTY FOR THE RIGHT REASON.
# Phase 9's shape: the input source built with `write(2, "MESSAGE-OUT\n", 12)` at all
# NINETEEN output statements, and the output source built with the IDENTICAL instrument
# inside `host_message`.  Both must mark exactly the same records -- 24 of the 30 argv
# rows, by name, and 0 of the 102 screens, 0 of ref-excmds.txt, 0 of ref-pty.txt and 0
# of ref-term.txt.  Same places, same times, different primitive.  It also settles
# `msg_puts_printf` and `exit_scroll`'s printf arm without removing them: the 24 marked
# rows are 23 `mainerr` and one `report_term_error`, so the other four speakers fire in
# ZERO of 106 records.
#
# THE COUNTING TRAPS, AND WHY THE ASSERTIONS ARE SHAPED AS THEY ARE:
#
#   * `printf` IS NOT AT 0.  13 -> 10, and none of the ten is a call: nine
#     `format(printf, ...)` attributes and the string "E767: Too many arguments for
#     printf()".  `assert printf at 0` FAILS ON A CORRECT PHASE.  The assertions that
#     work are `fprintf` 16 -> 0, `stderr` 17 -> 0, `fflush` 1 -> 0, `printf` 13 -> 10
#     and `nm -u`.
#   * `errno` DOES NOT MOVE, 3 -> 3, and `__errno_location` is REQUIRED still undefined.
#     It is held by `host_tty_set`'s and `musl_wait_for_input`'s two `== EINTR` tests,
#     both of them inside phase 20's host block, and it leaves at the split.  Removing
#     stdio has nothing to do with it -- said out loud, because a reader who watches
#     seven symbols go will look for the eighth.
#   * `msg_use_printf` 6 AND `msg_puts_printf` 3, UNCHANGED.  They are not dead: the
#     first returns TRUE 23 times in 106 records.  Removing them is a later phase's
#     question and would free nothing, the symbols being gone here.
#   * `host_message` AND `vim_host_message` ARE DIFFERENT WORDS to \b, which is why
#     their counts are separate -- phase 19 learnt that with `host_exit`.
#
# THE ONE THING THAT REALLY CHANGES AND NO RECORDING CAN SEE IS THE BUFFER'S BOUND.
# `mainerr`'s `str` and `report_term_error`'s `term` are argv, and a 1024-byte assembly
# buffer caps a message that used to be unbounded.  Both halves are pinned below: an
# option name of 900 characters must be the same 995 bytes on both binaries, and one of
# 2,000 must be 2,095 bytes on the input and exactly 1,023 here, with `-T` 2,039 against
# exactly 1,023.  A cap that drifted either way would fail.  The counts are RAW: the
# version banner's `__DATE__`/`__TIME__` differ between two builds and their LENGTH does
# not, so only the equality at 900 is scrubbed.

# THE BODY IS GO: tools/go/internal/check/zero21.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zcompare.py
#   tools/zerodelta.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero21-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero21-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero21 "$work" "$state"
