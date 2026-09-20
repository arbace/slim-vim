#!/bin/sh
# Zero phase 7 -- the editor loses every way to read a file.  See ZERO-GOAL.md.
#
# Usage: pipes/zero7-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# The other half of taking the filesystem away.  Phase 6 removed the six commands
# that put bytes on a disk; this one removes the command that takes them off it,
# `:read`, and with it the `:r !cmd` arm -- the last caller of the filter and shell
# plumbing whim left as stubs.  What remains of reading a file is `readfile()`
# itself, which the startup path still uses and which is the "nothing reads a byte"
# phase's (ZERO-PLAN.md P8); this phase asserts that it is untouched, by count.
#
# THREE ANCHORS, AND ONE FOLD THAT IS A JUDGEMENT.  Everything else is the sweep's
# (ZERO-GOAL.md rule 1: removal is computed, not listed), and six functions go
# without one of them being named here:
#
#   1. the `CMD_read` enumerator of `enum CMD_index`, one line;
#   2. the `cmdnames[]` row, one physical line, designated `[CMD_read] = {`;
#   3. `do_one_cmd`'s `if (ea.cmdidx == CMD_read) {...}` -- the parse that turns
#      `:r!` and `:r !cmd` into a filter -- deleted as TEXT rather than folded,
#      because its condition names the enumerator that is going.  It must go in the
#      same edit as anchor 1 or nothing declares what it reads.
#
# THE JUDGEMENT: `exarg_T.usefilter`.  Phase 6 removed one of its two writers
# (`:w >>` and `:w !cmd`) and anchor 3 removes the other, so after this edit the
# field is WRITTEN NOWHERE -- and `do_one_cmd` memsets the struct, so every reader
# is constantly FALSE.  No tool here can see that: tools/deadfields.py removes a
# field nothing NAMES, and gcc has no warning for a struct member that is only
# read.  So the six readers are folded by hand and the field goes with them, which
# is phase 4's argument for `exmode_active` in a smaller shape.  Measured on this
# input: folding costs 13 lines and gives a BYTE-IDENTICAL recording -- the fold
# changes no behaviour at all, it removes a test whose answer was already fixed.
#
# The alternative, leaving the field, was measured too and is a worse tree for the
# same 209 lines: `usefilter` would survive as a member nothing writes, seven tests
# of it would survive as dead branches, and the next phase to read this file would
# have to work out for itself that they can never be taken.
#
# THE TEXT THIS EDIT LEAVES DOES NOT COMPILE, and that is stated here because
# nothing else would say it.  One mention of `usefilter` survives the cut, in
# `ex_read` -- the function whose only reference was the row that just went -- and
# the field it names is gone.  The invariant at the end is the honest form of that,
# computed rather than listed: every surviving mention is inside a function
# definition, and no surviving `cmdnames[]` row names that function, which is the
# whole argument that funcreach.py takes it in the sweep's first round.
# tools/phasecheck.sh in pipes/zero7-check.sh is where "it compiles" is asserted.
#
# NO HANDLER IS DELETED BY NAME.  The row is the only reference a command handler
# has, so taking the row is what makes `ex_read` unreachable, and `do_bang`,
# `do_shell`, `do_filter`, `check_secure` and `prevcmd_is_set` follow it -- `:!` has
# not existed since whim, and phase 6 swept `ex_write`, which held `do_bang`'s other
# call (`:w !cmd`).  The check records the six as a measurement of what the sweep
# did.
#
# THE ROW FLOOR.  `cmdnames[]` goes 105 -> 104 rows, and create_cmdidxs's `names()`
# refuses a table of fewer than 100 -- a regex that stops matching otherwise yields
# a plausible all-zero index, so the floor is deliberate.  `zexcmds`
# enumerates the table through it, so crossing the floor would stop zero's command
# sweep rather than give a wrong answer.  After this phase the margin is FOUR rows,
# and ZERO-PLAN.md 3a gives it to the `:edit` phase, which must lower the floor.
#
# NO ENUMERATOR DUMP, for phase 6's reason.  Deleting one renumbers 46 survivors and
# every one is a `CMD_*`: `cmdnames[]` is DESIGNATED, so a row lands at its own
# enumerator whatever the numbering is, the `static_assert` on the row count catches
# a dropped pair, and all 104 surviving names are dispatched by `zexcmds`
# inside the declared delta.  There is no derived first-two-letters index in this
# file -- whim's Phase 80 took it with the 489 stub rows -- so nothing else depends
# on a position.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, exactly as pipes/zero2-edit.sh, zero4-edit.sh, zero5-edit.sh and
# zero6-edit.sh do it.  THE CORPUS CANNOT SEE THAT A FILE WAS READ: every one of
# `zcases`'s 102 cases types its own text and names no file, so `cmd_read`
# types `:read` with no file name and has only ever recorded `E32: No file name`.
# The only evidence that this phase removed reading rather than one error message is
# a probe that requires the OLD binary to pull a file off the disk, and that needs
# the old binary.  The source goes with it, as $state/old.c, for the before-and-
# after counts the check takes.
set -eu

work=${1:?usage: zero7-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero7-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero7 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  noread       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  noread       the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: the corpus cannot see a file being read, so the probes need a binary that still reads one"

# tools/phaserun.sh sweeps next, then runs pipes/zero7-check.sh.
