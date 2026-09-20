#!/bin/sh
# Zero phase 21 -- the messages are the editor's, the writing is the host's.
# See ZERO-GOAL.md.
#
# Usage: pipes/zero21-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# ZERO-PLAN.md 4c's second step, and the half of it that is not the screen:
# "`printf` for the messages that appear before there is a screen, which is itself a
# question for the host".  This phase answers it.  Every byte this file has ever put
# on a stream instead of a screen goes through one call the launcher installs, in
# EXACTLY phase 19's shape:
#
#     static void (*vim_host_message)(const char *msg, int len, int err);
#     vim_main(int argc, char **argv, void (*exit_fn)(int),
#              void (*message_fn)(const char *, int, int))
#         vim_host_message = message_fn;
#     host_message()   beside host_exit(), in the launcher, write(err ? 2 : 1, ...)
#
# and `<stdio.h>` goes with them: TWELVE DIRECTIVES BECOME ELEVEN.  That is the second
# time a zero phase has removed one (phase 16 was the first), and it is the same
# argument -- this is the header the phase's symbols came from, the charter permits a
# removal and forbids an addition, and from here the "no stdio stream" invariant phase
# 13 asserted is visible in the directive list as well as in `nm -u`.
#
# UNLIKE PHASE 20, THIS ONE REALLY FREES SYMBOLS, and the reason is the rule phase 20
# stated: a symbol leaves when its last CALLER leaves the file.  `printf` and
# `fprintf` were being CALLED here, not merely mentioned, and deleting the calls
# deletes the callers.  `nm -u` 24 -> 17, the gone set exactly
# `fflush fputc fputs fwrite printf putchar stderr`, and NOTHING arrives.
#
# FOUR OF THOSE SEVEN ARE NAMED NOWHERE IN THE SOURCE.  `fputc`, `fputs`, `fwrite` and
# `putchar` are what gcc emits for `printf("%s", x)` and `fprintf(stderr, "%s", x)`;
# the file has never contained the word.  They were PREDICTED to leave with the
# construct and then VERIFIED by building -- which is the whole reason
# pipes/zero21-check.sh states the claim as one `comm` with an empty `arrived` side
# rather than as a count.
#
# ------------------------------------------------------------------------------------
# THE INVENTORY, MEASURED ON THE INPUT: 20 STATEMENTS IN FIVE FUNCTIONS
#
#   msg_puts_printf     2 printf, 2 fprintf   whatever message was being printed,
#                                             `info_message` choosing the stream
#   exit_scroll         1 printf, 1 fprintf   "\n" / "\r\n" on the way out
#   report_term_error   7 fprintf             `'<term>' not known, defaulting to
#                                             'xterm'`, before there is a screen
#   set_termname        1 fflush              ELEVEN LINES BELOW the call above, and
#                                             not inside report_term_error at all
#   mainerr             6 fprintf             the version banner and the argv refusal
#
# THE BRIEF THIS PHASE WAS WRITTEN FROM COUNTED 21 STATEMENTS IN SIX FUNCTIONS, and
# the sixth was `nv_esc`'s `Type :qa! and press <Enter> to abandon all changes`.  It
# went at phase 20, with `stdout_isatty` and the `out_redir` arm it sat in.  So
# `fprintf` is SIXTEEN here and not seventeen and `stderr` is seventeen and not
# eighteen, and the edit counts the input rather than trusting the survey.
#
# FORMATTING STAYS IN THE CORE, and that is what turns 20 statements into 8 call
# sites.  `vim_snprintf` has been the only formatter in the file since phase 14, so
# the two multi-part speakers assemble into a local buffer and hand over one string,
# and the other six sites are one call each with the text unchanged.  MEASURED with a
# SOCK_SEQPACKET socketpair as fd 2, which preserves write boundaries exactly: `-Q`
# was 6 writes of 96 bytes and is 1 write of 96 bytes; `-T no-such-term-9x` was 5 of
# 54 and is 1 of 54.  The same bytes, one syscall.
#
# THE BOUND THAT COMES WITH THE BUFFER, STATED RATHER THAN DISCOVERED.  `mainerr`'s
# `str` and `report_term_error`'s `term` are both argv, so a 1024-byte buffer caps a
# message that used to be unbounded.  MEASURED on both binaries: an unknown option of
# 900 characters is byte-identical, 995 bytes of stderr either side, and one of 2,000 is
# 2,095 bytes on the input and exactly 1,023 here; a `-T` of 900 is identical at 939 and
# one of 2,000 is 2,039 against the same 1,023.  The turn is at 930, where 1,025 becomes
# 1,023.  The cap is deliberate -- `IOSIZE` is 1024 and it is what every other message
# in this editor is built in -- and pipes/zero21-check.sh pins both halves of it, the
# identity at 900 and the exact cap at 2,000, so neither can drift unnoticed.
#
# ------------------------------------------------------------------------------------
# WHAT IS NOT DONE HERE, AND IT IS A DECISION AND NOT AN OVERSIGHT
#
# `msg_puts_printf()` STAYS, ALL 75 LINES OF IT, and so does `exit_scroll`'s printf
# arm.  `msg_use_printf()` is not dead: it returns TRUE in 23 of 106 records -- once in
# each `mainerr` record, from `mch_exit` -> `exit_scroll()`'s else arm ->
# `msg_clr_eos_force()`, where `full_screen` is FALSE and the body it guards therefore
# does nothing.  It is never true at `msg_puts_attr()`'s call site, so
# `msg_puts_printf()` is entered ZERO times against a control that marks 100 of 102
# screens.  That is phase 12's kind of dead and not phase 9's: the branch CAN be taken
# and never is.  Folding it at `msg_clr_eos_force()` would run `screen_fill()` with no
# valid screen; folding it at `msg_puts_attr()` would hand a message to
# `msg_puts_display()` on a screen the test has just called unusable.  Removing it is a
# separate phase with a separate question -- "the screen is always usable in this
# build" -- and phase 12's kind of evidence to gather, and it would free nothing,
# because the symbols are gone HERE.
#
# `__errno_location` IS NOT THIS PHASE'S EITHER, and it is said out loud because a
# reader who sees stdio leave will look for it.  MEASURED: `errno` is 3 mentions --
# `#include <errno.h>` and two uses, `host_tty_set`'s `tcsetattr(...) == -1 && errno ==
# EINTR` and `musl_wait_for_input`'s `ret == -1 && errno == EINTR`.  Phase 20 moved both
# INTO the host block and kept them.  They leave when the file splits, not here, and
# this phase's `comm` requires `__errno_location` still present for exactly that reason.
#
# `write` IS NOT ADDED TO `zhostonly`'s VOCAB, and the reason is that it would
# be false: `mch_write()` still holds one `write(1, ...)`, which is ZERO-PLAN.md 4c's
# remaining step and not this one.  What IS assertable, and what pipes/zero21-check.sh
# asserts instead, is that the whole file now has exactly TWO bare `write()` call sites
# -- `mch_write`'s and `host_message`'s -- where before this phase it had one and a
# stdio layer beside it.  Adding the stdio words to that tool's VOCAB is impossible for
# a different reason and worth writing down: phase 20's own output says `fprintf`
# sixteen times in the core, so a VOCAB that forbade it would fail `make zero-verify`
# at r20.
#
# THE COUNTING TRAP, WHICH IS PHASE 19'S `exit` TRAP WITH DIFFERENT WORDS.
# `assert printf at 0 mentions` FAILS ON A CORRECT PHASE.  `printf` is 13 words in the
# input and only THREE are calls: nine are `__attribute__((format(printf, ...)))` on
# `smsg`/`smsg_attr`/`semsg`/`siemsg`/`vim_snprintf` and two `format(printf,3,0)`
# prototypes, and one is inside the string `"E767: Too many arguments for printf()"`.
# 13 -> 10 is the true figure.  `assert 'printf(' at 0` fails on `vim_snprintf(`,
# `msg_use_printf(`, `msg_puts_printf(` and `vim_vsnprintf_typval(`.  The assertions
# that work are `fprintf` 16 -> 0, `stderr` 17 -> 0, `fflush` 1 -> 0, `printf`
# 13 -> 10, and `nm -u`.
set -eu

work=${1:?usage: zero21-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero21-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero21 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  message      the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  message      the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from -- the recording, the write boundaries on fd 2 and the instrumented pair are all PAIRS, and this is the left-hand side"

# tools/phaserun.sh sweeps next, then runs pipes/zero21-check.sh.
