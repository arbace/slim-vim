#!/bin/sh
# Zero phase 6 -- the editor loses every way to write a file.  See ZERO-GOAL.md.
#
# Usage: pipes/zero6-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# A core does not own a disk.  Reading and writing files is the host's business
# (ZERO-GOAL.md, the charter), and this is the first half of taking the filesystem
# away: the six Ex commands that put bytes on a disk -- `:write :wq :xit :exit
# :update :saveas` -- and, with them, everything only they reached.
#
# FOUR ANCHORS, AND NOT ONE FOLD.  Everything else is the sweep's (ZERO-GOAL.md
# rule 1: removal is computed, not listed).  The alternative was measured: an edit
# that also deletes `ex_write`, `ex_update`, `ex_exit`, `do_write`, `check_writable`,
# `check_overwrite`, `not_writing` and `check_readonly` by name produces a
# BYTE-IDENTICAL swept file, in 3 rounds against 4 and 17 seconds against 22.  So
# the eight names are not written here: the table row is the only reference a
# command handler has, and taking the row is what makes the handler unreachable.
#
#   1. the six enumerators of `enum CMD_index`, one line each;
#   2. the six `cmdnames[]` rows, one physical line each, designated `[CMD_x] = {`;
#   3. `nv_Zet`'s `ZZ`, which runs the string "x": `do_cmdline_cmd("x")` -> "q!";
#   4. `do_one_cmd`'s `:w>>` / `:w!` parse, an `if (ea.cmdidx == CMD_write ||
#      ea.cmdidx == CMD_update) {...}` with no else -- deleted as TEXT rather than
#      folded, because its condition names two enumerators that are going.  It must
#      go in the same edit as anchor 1 or nothing declares what it reads.
#
# `ZZ` BECOMES `q!`, WHICH IS A DECISION AND NOT A CONSEQUENCE.  `nv_Zet` runs a
# command STRING, so nothing here breaks at compile time: left alone, `ZZ` would
# type `:x` at a command that no longer exists and answer E492.  The user's settled
# decision is that ZZ is ZQ, and `case:zz_key` moves either way -- E32 today, E492
# if the string is left, nothing at all with `q!` -- so this phase owns it and says
# so rather than leaving a dead command named in the source.  ZERO-PLAN.md gives it
# to the `:q` phase; that row is annotated as built.
#
# THE TEXT THIS EDIT LEAVES DOES NOT COMPILE, and that is stated here because
# nothing else would say it.  Six mentions of the six enumerators survive the cut --
# `CMD_saveas` five times and `CMD_wq` once -- every one of them inside `ex_write`,
# `do_write` or `ex_exit`, which are exactly the functions whose only reference was
# the row that just went.  `funcreach.py` deletes them in the sweep's first round,
# and `tools/phasecheck.sh` in pipes/zero6-check.sh is where "it compiles" is
# asserted.  The invariant below is the honest form of that: every surviving mention
# is inside a function definition, and no surviving `cmdnames[]` row names that
# function.
#
# THE ROW FLOOR.  `cmdnames[]` goes 111 -> 105 rows, and
# `create_cmdidxs`'s `names()` REFUSES a table of fewer than 100 -- a regex
# that stops matching otherwise yields a plausible all-zero index, so the floor is
# deliberate.  ``zexcmds`` enumerates the table through it, so crossing the
# floor would stop zero's command sweep rather than give a wrong answer.  After this
# phase the margin is FIVE ROWS.  ZERO-PLAN.md 3a: the `:edit` phase is the one that
# spends it, and it is the phase that must lower the floor.
#
# NO ENUMERATOR DUMP HERE, and phase 5 had one for a reason that does not apply.
# Deleting the six renumbers 89 survivors, all of them `CMD_*` -- measured with
# tools/enumvals.sh: 1,323 enumerator values in, 1,303 out, 20 gone (the six plus
# fourteen single-constant explicit-value enums the sweep takes with their types),
# 89 moved and every one a command index.  Phase 5's `main_errors[]` was a table
# indexed by the enumerators it removed, with the rows written in order, so a wrong
# index was invisible to the build and DWARF was the only witness.  `cmdnames[]` is
# DESIGNATED: a row lands at its own enumerator whatever the numbering is, the
# `static_assert` on the row count catches a dropped pair, and every one of the 105
# names is dispatched by `zexcmds` in the declared delta.  Three checks the
# build cannot dodge, and none of them needs the values.
#
# NOT create_cmdidxs --check, for pipes/zero2-edit.sh's reason: the derived
# first-two-letters index went with the table whim reduced, and the tool raises
# rather than reporting nothing.  Its `names()` is called, which is the part that
# still means something here.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, exactly as pipes/zero2-edit.sh, zero4-edit.sh and zero5-edit.sh do it.  It
# is not decoration: THE CORPUS CANNOT SEE WRITING.  ``zcases``'s `cmd_write`
# types `:write` with no file name and has only ever recorded `E32: No file name`,
# so every screen the baselines hold is of an editor that failed to write.  The only
# evidence that this phase removed writing rather than one error message is a probe
# that requires the OLD binary to leave a file on the disk, and that needs the old
# binary.  The source goes with it, as $state/old.c, for the before-and-after counts
# the check takes.
set -eu

work=${1:?usage: zero6-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero6-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero6 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  nowrite      the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  nowrite      the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: the corpus cannot see writing, so the probes need a binary that still writes"

# tools/phaserun.sh sweeps next, then runs pipes/zero6-check.sh.
