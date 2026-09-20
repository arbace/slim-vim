#!/bin/sh
# Zero phase 30 -- the message fold: msg_puts_printf() and the branch that reaches it.
# See ZERO-PLAN.md 4c, ZERO-GOAL.md, and .claude/briefs/zero-last-two.md PART ONE.
#
# Usage: pipes/zero30-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# ONE FOLD, AND ONLY ONE.  `msg_puts_attr_len()` ends in
#
#     if (msg_use_printf())  { msg_puts_printf((char_u *)str, maxlen); }
#     else                   { msg_puts_display((char_u *)str, maxlen, attr, FALSE); }
#
# and the true arm is never taken.  The test STAYS -- `msg_use_printf()` is a live
# predicate and this phase leaves it at six mentions -- and the arm becomes two lines
# that speak to the host directly:
#
#     host_message((char *)str, maxlen, !info_message);
#     msg_didout = TRUE;
#
# With it go `msg_puts_printf()` (75 lines), its prototype, and `vim_strlen_maxlen()`
# and its prototype, which the sweep finds because that function held its only call.
#
# WHICH KIND OF DEAD THIS IS, AND IT IS NOT PHASE 9'S.  Phase 9 removed code that
# COULD NOT RUN; this removes code that CAN run and never does.  `msg_use_printf()`
# returns TRUE 23 times in a single recording -- once per `mainerr` row of
# ref-argv.txt -- so the predicate is alive; it is never TRUE at THIS call site.  That
# is phase 12's kind, and phase 12's evidence is what is owed: an instrument at the
# site, a control that proves the instrument works, and probes that try hard to make
# it fire.  pipes/zero30-check.sh has all three -- the input built twice with
# `write(2, "PP-ENTERED\n", 11)`, first in `msg_puts_printf()` (0 of 106 records) and
# then in `msg_puts_display()` (103 of 106, the identical instrument), plus 32 stream
# probes and 4 deadly-signal probes.
#
# WHY THE MESSAGE IS KEPT RATHER THAN DROPPED.  Deleting the arm's body outright is
# five lines smaller and records identically, and it was REJECTED: a phase about
# removing dead CODE must not quietly remove a CAPABILITY.  `host_message()` is
# already the core's declared way to speak when there is no screen (phase 21 wrote it,
# phase 25 made it a direct call), and `host_message(msg, len, err)` treats `len < 0`
# as `strlen` and `len >= 0` as an exact count -- which is `msg_puts_printf`'s own
# `maxlen` contract, MEASURED by reading both.  The call is never executed, so
# "exactly equivalent" is not claimed: what the two lines do not reproduce is the
# CR-before-NL insertion and the `msg_col` bookkeeping, neither of which any recording
# or probe can reach.
#
# ------------------------------------------------------------------------------------
# TWO FOLDS THAT LOOK LIKE THIS ONE AND ARE NOT DONE.  Each is a RESULT of this phase
# and not an omission, and each was measured on a binary built for the purpose.
#
# 1. `msg_clr_eos_force()`'s test CANNOT BE FOLDED SAFELY, and this is where a
#    corpus-only check would ship a bug.  Its true arm writes `t_CD`/`t_CE`; its false
#    arm calls `screen_fill()` twice.  Folding to the false arm leaves the RECORDING
#    BYTE-IDENTICAL -- `screen_fill()` returns early on `ScreenLines == nullptr`, and
#    `ScreenLines` is NULL in all 23 `mainerr` cases, which are the only 23 places the
#    predicate is TRUE in a recording.  Two probes see it and nothing else does:
#    `t_ti_stopterm` (`:set t_ti=X`, `:set t_te=Y`, `ZQ`) goes 2,266 -> 2,280 bytes,
#    and `hup_clean` (`kill -HUP` on a clean pty) goes 2,124 -> 2,142, the extra
#    eighteen being `\x1b[24;63H\x1b[K\x1b[24;1H` AFTER `Vim: Finished.` -- the editor
#    erasing the last line of a screen it has just declared unusable, on its way out.
#    GUARDING WITH `msg_check_screen()` INSTEAD IS NOT EQUIVALENT: that drops the
#    `swapping_screen() && !termcap_active` disjunct, and that disjunct is exactly what
#    `t_ti_stopterm` reaches -- measured, it moves the same two probes, to the same two
#    numbers.  The check builds both of those and requires them to move.
#
# 2. `exit_scroll()`'s printf arm IS ALIVE, and phase 21 was wrong to name it a
#    follow-up beside `msg_puts_printf()`.  pipes/zero21-check.sh says the two "fire in
#    ZERO of 106 records"; that is true of the CORPUS and true of the editor only for
#    the first.  MEASURED: the arm fires with no signal at all in three of this phase's
#    32 stream probes -- `t_ti_more`, `debug_more` and `term_ti_then_ti`, each `:set
#    t_ti=X` (or `-T debug`) plus a paged `:set all` plus exit -- and in three of the
#    four deadly-signal probes.  Folding it to `out_char('\n')` is not a crash risk:
#    `out_char('\n')` emits `\r` first, so the bytes are the same two.  It moves them
#    from FD 2 TO FD 1, which on a pty where both are the same device is invisible and
#    therefore undeclarable.  It belongs to whichever phase decides the core writes
#    nothing to fd 2 at all -- ZERO-PLAN.md 4c's host-boundary question, not a tidy-up.
#    The check builds that fold too and requires it to move three stream probes and
#    three signal probes, which is the evidence that THIS phase did not disturb it.
#
# ------------------------------------------------------------------------------------
# THE COUNTING TRAP, MEASURED.  `    if (msg_use_printf())` at four spaces is a
# SUBSTRING of the same line at eight: `str.count()` says 3 where
# `grep -c '^    if (msg_use_printf())$'` says 2, the third match being
# `exit_scroll`'s, indented eight.  So the anchor is the whole four-line block, whose
# count is 1.  And there are FOUR call sites, not three: the fourth is written
# `if (!msg_use_printf())` in `hit_return_msg()` and an edit that greps for the
# positive spelling misses it.  All three sites this phase does not touch are asserted
# present VERBATIM below, before and after.
set -eu

work=${1:?usage: zero30-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero30-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a second
# time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero30 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  msgfold      the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  msgfold      the input is $state/old, $(stat -c%s "$state/old") bytes, built with SOURCE_DATE_EPOCH=0 beside the source it came from -- the check probes it and the output side by side, and builds three further binaries from THIS phase's output to show what folding the other two sites would have done"

# tools/phaserun.sh sweeps next, then runs pipes/zero30-check.sh.
