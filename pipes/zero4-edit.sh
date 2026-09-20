#!/bin/sh
# Zero phase 4 -- no streaming Ex.  See ZERO-GOAL.md.
#
# Usage: pipes/zero4-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# An embeddable core is driven by a host through a screen and a keyboard.  Ex mode
# is the opposite arrangement: the editor takes stdin over, prints its own prompt,
# reads a line at a time and writes the result back on stdout, and it brings a
# second mode with it -- silent mode, which redirects the whole message layer into
# `printf` and buffers stdout through setvbuf().  Both are entered from the command
# line (`-e`, `-E`, `-s`, `-v`) or from the keyboard (`Q`, `gQ`), and neither has
# any meaning for a core that is handed its input and its screen.
#
# WHAT GOES.  `do_exmode()` and `getexmodeline()`, the loop and the line reader;
# `nv_exmode()` and `nv_g_cmd`'s `case 'Q'`, the two keys that call them; the four
# command-line options; and then the two globals they were the only writers of --
# `exmode_active` (49 mentions) and `silent_mode` (23) -- which become constantly
# FALSE and fold away at every one of their readers.
#
# THE TWO COUNTS ARE ASSERTED BEFORE THE CUT AND AFTER IT, and so are the other
# nineteen identifiers that go with them.  A fold is only sound while the variable
# really is constant, so "every mention is accounted for" is the whole argument:
# 49 and 23 before, 0 and 0 after, counted by `\b` because `pending_exmode_active`
# contains `exmode_active` and a plain substring count says 53.
#
# EVERY FOLD IS COUNTED AND SCOPED TO ONE FUNCTION (tools/cutil.py), because the
# polarity is not the same at every site and a fold applied to "the first one" of
# several is a guess:
#
#   * `if (exmode_active)`            folds NEVER -- the body is Ex mode's
#   * `if (!exmode_active)`           folds ALWAYS -- the body is everyone else's
#   * `if (exmode_active != EXMODE_NORMAL)` in msg_start() folds **ALWAYS**, because
#     0 != 1 is TRUE.  It reads like its neighbours and is their opposite, and
#     getting it backwards would quietly give every message Ex mode's newline.
#
# WHAT STAYS, and the reader that forces each:
#   * `getexline()` -- `:append`, `:insert` and `:change` read their lines through
#     it, not through the Ex-mode reader.  It keeps `ex_at` and `nv_colon`.
#   * `exe_commands()` -- it runs the `+{command}` list, which is how every harness
#     here drives the editor.  Only its last statement, an `if (!exmode_active)`,
#     folds.
#   * everything the argv phase owns: `case NUL`'s else arm (`EDIT_STDIN`,
#     `read_cmd_fd = 2`), `case '-'` and `had_minmin`, the file argument,
#     `ME_TOO_MANY_ARGS` and its `main_errors[]` row, `case 'T'`, the `+cmd` arm.
#   * `cmdwin` and `want_full_screen`, which lose a reader each and keep one.
#
# `-s` IS NOT IN THE DECLARED DELTA and the reason is worth stating: it was never
# an option on its own.  `case 's'` set silent mode only `if (exmode_active)` and
# called `mainerr(ME_UNKNOWN_OPTION)` otherwise, so `vim -s` already failed before
# this phase and fails in the same way after it.  `-e`, `-E`, `-e -s` and `-v` do
# move, and are declared in pipes/zero.delta.
#
# THREE FUNCTIONS ARE DELETED BY NAME rather than left to the sweep.  A function
# whose address is taken is reachable as far as gcc is concerned: `getexmodeline`
# is passed to `do_cmdline()` and compared with `getline_equal()`, so -Wunused-
# function never names it, and `do_exmode` keeps it alive through a call the sweep
# would have to remove first.  `nv_exmode` goes the same way, because an `nv_cmds[]`
# row is a reference: the row is REPOINTED at `nv_error` and never deleted -- a
# deleted row shifts `nv_cmd_idx[]` and every key past the hole resolves to another
# key's handler (CLAUDE.md; `nvidx` is what would catch it).
#
# SIX WRITE-ONLY LEFTOVERS GO BY HAND, because no warning covers a variable that is
# assigned and never read: `ex_pressedreturn`, `ex_no_reprint` (seven writes),
# `ex_exitval`, `previous_got_int`, `use_plus_cmd` and `exmode_was`.  gcc's
# -Wunused-but-set-variable sees a local, not a file-scope static, and
# tools/deadsweep.py only deletes what gcc names.
#
# THE SWEEP TAKES the rest: `exmode_active`, `silent_mode`, `pending_exmode_active`,
# `s_vbuf`, `exmode_plus`, `e_at_end_of_file`, the `getexmodeline` and `nv_exmode`
# prototypes, the three single-constant enums (`EXMODE_NORMAL`, `EXMODE_VIM`,
# `BO_EX` -- each with an explicit value, so nothing renumbers), and
# `mch_input_isatty()`, with the fifth of the five `isatty()` calls.
#
# `check_tty()` IS PHASE 2'S AS MUCH AS THIS ONE'S.  Phase 2 took its warning branch
# and kept the `if (exmode_active)` one deliberately, saying Ex mode was a later
# phase's.  This is that phase, and nothing is left -- which is why `isatty` goes
# from five calls to four here and not there.  It is deleted by name rather than
# folded, for the reason given at the site.
#
# THAT INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, exactly as pipes/zero2-edit.sh does it: pipes/zero4-check.sh requires the
# OLD binary to enter Ex mode and the new one to refuse, which is the difference
# between a probe and a formality.
set -eu

work=${1:?usage: zero4-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero4-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero4 "$f"

# NOT create_cmdidxs --check: the derived first-two-letters index went with
# the command table whim reduced, and there are no `ex_cmdidxs.h` banners left for it
# to find -- it raises rather than reporting nothing (pipes/zero2-edit.sh says the
# same).  Nothing here touches the command table.
#
# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  noexmode     the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  noexmode     the input binary is $state/old, $(stat -c%s "$state/old") bytes, for the check's before-and-after"

# tools/phaserun.sh sweeps next, then runs pipes/zero4-check.sh.
