#!/bin/sh
# Zero phase 8 -- the editor loses every way to name something else to edit.
# See ZERO-GOAL.md.
#
# Usage: pipes/zero8-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Phases 6 and 7 took the commands that put bytes on a disk and the one that takes
# them off it.  This one takes the commands that point the editor AT a file --
# `:edit :enew :ex :visual :view` -- and the four Normal-mode keys that do the same
# thing from the buffer's own text, `gf gF [f ]f`.  What is left of opening
# anything is `readfile()` and `open_buffer()`, which the startup path still uses
# and which are the "nothing reads a byte" phase's (ZERO-PLAN.md P8); this phase
# asserts by count that both are untouched.
#
# WHAT THE FIVE COMMANDS ACTUALLY WERE, measured on the input binary in a directory
# holding a file called `keys`: `do_exedit` is thirty lines -- a lock guard, a
# `readonlymode` save/set/restore testing CMD_view and CMD_enew, `setpcmark()` and
# one `do_ecmd()` call.  So `:ex` and `:visual` are `:edit` spelled differently
# (their Ex-mode escape has had nothing to escape from since phase 4), `:view` is
# `:edit` with `'readonly'` set, and `:enew` is `:edit` with a NULL file name.  One
# handler, `ex_edit`, is all five rows, which is why they go together.
#
# SIX ANCHORS, and everything else is the sweep's (ZERO-GOAL.md rule 1: removal is
# computed, not listed).  Sixteen functions go without one of them being named
# here, seventeen with anchor 6:
#
#   1. five enumerators of `enum CMD_index`, one line each;
#   2. five `cmdnames[]` rows, one physical line each, designated `[CMD_x] = {`;
#   3. `do_one_cmd`'s `curbuf_locked()` exemption, which names `CMD_edit` in a
#      conjunct -- `CMD_file` STAYS, being the `:file` phase's.  It must go in the
#      same edit as anchor 1 or nothing declares what it reads, and it is the one
#      anchor outside the table and the keys: an edit shaped like the table forgets
#      it, and the build is what catches that.
#   4. `nv_g_cmd`'s `case 'f': case 'F': nv_gotofile(cap); break;` arm.  `gf` and
#      `gF` fall to `default: clearopbeep` with the rest of the unused `g` keys.
#   5. `nv_brackets`'s `if (cap->nchar == 'f') { nv_gotofile(cap); } else { ... }`,
#      where the else is the whole rest of the function.  `[f` and `]f` fall into
#      the chain that ends in `clearopbeep`.
#   6. `do_one_cmd`'s `if (ea.argt & EX_ARGOPT) { while (... getargopt(&ea) ...) }`.
#
# NO `nv_cmds[]` ROW IS TOUCHED, and that is the hazard this phase does not have.
# There is no row for `gf`, `gF`, `[f` or `]f`: they are arms inside two handlers
# whose `g`, `[` and `]` rows dispatch dozens of other keys, so nothing is deleted
# from the table and nothing renumbers.  The check presses fifty of those keys on
# both binaries and requires exactly four to move.
#
# ANCHOR 5 IS NOT A `cutil.fold_never`, AND THE REASON IS INDENTATION.  fold_never
# keeps an `else` body by dedenting it four columns, which is right when the body
# was written one level in.  This one was not: upstream's `else` here has no braces
# at all (the `if` is inside `#ifdef FEAT_SEARCHPATH`), so slim's bracing pass put
# a `{`/`}` round the rest of the function and left every line at the function's
# own four columns.  Dedenting would put forty lines at column zero and no tool
# here would ever say so -- CLAUDE.md's "one thing no tier can see".  So the head
# and the matching closer are deleted as counted text, by brace matching, and the
# body keeps the indentation it already had.
#
# ANCHOR 6 IS WORTH ITS LINES, and it is measured rather than argued.  `EX_ARGOPT`
# -- `++ff=`, `++enc=`, `++bin`, `++edit` -- was on five rows: `:read`, which phase
# 7 took, and these four.  After anchor 2 it is on NONE, so the block can never be
# entered, `getargopt()` can never run, and `exarg_T.read_edit` is written by
# nothing and read by nothing.  Deleting the block hands all three to the sweep.
# Measured: 30 lines, one more function, and a recording BYTE-IDENTICAL to the one
# the five anchors alone produce -- `++edit` was only ever accepted by the commands
# this phase removes, so there is nothing to declare.
#
# `EX_CMDARG` REACHES ZERO ROWS TOO AND IS LEFT ALONE, deliberately.  Its two
# fields are `do_ecmd_cmd`, which after this phase has four mentions and no writer,
# and `do_ecmd_lnum`, which has two -- and `do_ecmd_lnum` is written through
# `eval_vars()`, which is the buffer-name phase's.  Folding round that is that
# phase's to do; this one names the counts so that a later widening has to move
# them.
#
# `'undoreload'` STAYS, AND THE ROW IS NOT THIS PHASE'S.  `p_ur` has three mentions
# -- the declaration, one reader inside `do_ecmd` and the option row -- and after
# this phase two and no reader.  Removing the row would change what `:set ur?`
# answers, which nothing here sweeps, so the delta could not be checked; and
# ``orphanopts`` refuses the opposite direction, a global whose row has
# gone.  The check asserts `p_ur` at exactly 2 with its row intact, and the
# manifest carries `uses options:11 files:8 mechanical` for the phase that takes it.
#
# THE ROW FLOOR IS CROSSED HERE, AND THE FLOOR MOVES IN THIS COMMIT.  `cmdnames[]`
# goes 104 -> 99 and create_cmdidxs's `names()` refused a table of fewer than 100 --
# not with "too few rows" but with `no command table found in either shape`, because
# names() tries both parsers with check=False and neither answer clears the bar.
# `zexcmds` enumerates zero's whole Ex sweep through names(), so the old
# floor would have stopped the sweep, tools/zerodelta.sh, the recording and every
# later phase's check rather than giving a wrong answer.  ZERO-PLAN.md decision 8:
# lowered deliberately, to 80, in the phase that crosses it and in the same commit,
# with the reason in the tool's own docstring.  The margin is 19 rows and the next
# row the plan removes is `:file`'s.
#
# THE TEXT THIS EDIT LEAVES DOES NOT COMPILE, as phases 6 and 7 leave theirs, and
# the invariant at the end is the honest form of that, computed rather than listed:
# every surviving mention of a deleted enumerator is inside a function definition,
# and no surviving `cmdnames[]` row names that function -- which is the whole
# argument that funcreach.py takes it in the sweep's first round.
# tools/phasecheck.sh in pipes/zero8-check.sh is where "it compiles" is asserted.
#
# NO HANDLER IS DELETED BY NAME.  The row is the only reference a command handler
# has, so taking the five rows is what makes `ex_edit` unreachable, and `do_exedit`,
# `do_ecmd` and thirteen more follow it.  The check records the sixteen as a
# measurement of what the sweep did.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, exactly as pipes/zero2-edit.sh, zero4-edit.sh, zero5-edit.sh, zero6-edit.sh
# and zero7-edit.sh do it.  THE CORPUS SEES TWO CASES OF THIS PHASE and neither of
# them opens a file: `cmd_edit` types `:edit` with no file name and `key_gf` presses
# `gf` on a word that names nothing.  The only evidence that this phase removed
# opening a file rather than two error messages is a probe that requires the OLD
# binary to pull one off the disk, and that needs the old binary.  The source goes
# with it, as $state/old.c, for the before-and-after counts the check takes.
set -eu

work=${1:?usage: zero8-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero8-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero8 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  noedit       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  noedit       the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: the corpus only sees :edit with no file name and gf on a word that names nothing, so the probes need a binary that still opens one"

# tools/phaserun.sh sweeps next, then runs pipes/zero8-check.sh.
