#!/bin/sh
# Zero phase 10 -- the buffer has no name.  See ZERO-GOAL.md.
#
# Usage: pipes/zero10-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# Phases 6, 7 and 8 took every way to ASK for a file and phase 9 took the machinery
# that read one.  What is left of the filesystem in this editor is a NAME: three
# char_u* fields on every buffer -- `b_ffname`, `b_sfname`, `b_fname` -- and the one
# command that could still set them, `:file`.  This phase takes the command, stops
# `buflist_new()` naming the buffer it makes, and folds the sixteen places that ask
# what the name is.  After it the three fields are written nowhere, the sweep takes
# them, and `[No Name]` is no longer one of the answers the editor can give but the
# only one.
#
# IT IS ALSO WHERE THE CORE STOPS ASKING THE FILESYSTEM QUESTIONS OF ITS OWN ACCORD.
# Three libc symbols go, and each for the reason of one part below:
#
#   stat      `mch_getperm()`, reached from `find_file_in_path()`, which part G
#             makes unreachable: CTRL-F and CTRL-P extract a word from the buffer
#             and nothing looks for it on a disk.
#   getcwd    `mch_dirname()`, whose three callers were `shorten_fname()`,
#             `shorten_fnames()` and `mch_FullName()`.  Part F takes the second and
#             the sweep the other two.
#   strerror  `mch_dirname()`'s error arm, and nothing else's.
#
# SEVEN PARTS, A to G, and every removal that is not one of them is the sweep's
# (ZERO-GOAL.md rule 1).  Sixty functions go and this file names not one of them.
#
#   A  `:file` goes: the enumerator, the cmdnames[] row, and BOTH of do_one_cmd's
#      CMD_file tests -- the `curbuf_locked()` conjunct phase 8 deliberately kept,
#      and the second test below it.  All in one edit with the enumerator, or the
#      text does not compile.  `ex_file` -> `rename_buffer` -> `setfname` then die
#      by the sweep; `fileinfo()` SURVIVES, having three other callers.
#   B  `buflist_new()` never names: its one call site already passes NULL, NULL, so
#      both parameters go with the `fname_expand`/`stat`/`buflist_findname_stat`
#      prologue, the `if (ffname != NULL)` assignment, the failure arm's frees and
#      the `st.st_dev` block.
#   C  the sixteen folds, one per site, each with the constant it takes written out
#      here.  `== NULL` is TRUE and folds always; `!= NULL` is FALSE and folds
#      never.
#   D  `EX_XFILE` reaches zero rows -- `:file` was its last one -- so do_one_cmd's
#      `expand_filename()` call can never be entered.  Folding it never is what
#      hands the sweep 32 functions and some 1,300 lines, the same shape as phase
#      8's EX_ARGOPT.
#   E  `readonlymode` and `b_dev_valid`'s assignment, each write-only after C and
#      B, and neither of them anything a warning or a sweep tool can see.
#   F  `shorten_fnames()` loses the cwd it fetched for a now-empty
#      `shorten_buf_fname()`.
#   G  `find_file_name_in_path()`'s `FNAME_EXP` arm.
#
# FOLD `buflist_name_nr` AT ITS CALLERS, NEVER IN PLACE, and the agent that surveyed
# this phase made the mistake first.  Its body is `buf = buflist_findnr(fnum); if
# (buf == NULL || buf->b_fname == NULL) return FAIL; *fname = buf->b_fname; ...
# return OK;`.  Folding the whole `if` away gives a function that returns OK with
# `*fname` never written -- a silent behaviour change in the direction that crashes.
# What is true is that it returns FAIL ALWAYS, so the fold belongs at
# `getaltfname()` and at `ex_display()`, and only then is it uncalled and the
# sweep's.
#
# THREE SITES HAVE AN `else` AND cutil.fold_always REFUSES THEM, by design: keeping
# a body and dropping an else is not what it does.  fileinfo(), set_b0_fname() and
# get_trans_bufname() use the local fold_always_else() below, which keeps the if
# body dedented four columns -- right only because each of the three is written one
# level inside its function, which was read and not assumed, phase 8's anchor 5
# being what a wrong dedent costs.  And FOUR MORE are a function whose whole body is
# the `if`: buf_spname(), buf_get_fname(), check_fname() and getaltfname().
# fold_always there leaves an unreachable `return buf->b_fname;` behind -- measured
# -- which no sweep tool removes and which would keep `b_fname` alive for ever.
# Those four are exact-text rewrites of the body.
#
# THE TWO FOLDS IN eval_vars() ARE NOT MADE, and that is a correction to the brief
# this phase was written from.  Both of its `if (b_fname == NULL)` arms are inside a
# function part D makes unreachable: `expand_filename()` and
# `expand_wildcards_eval()` are its only callers and both go.  Folding inside text
# the sweep deletes changes no output and states nothing, so rule 1 applies -- the
# check requires `eval_vars` at 0 mentions afterwards, which is the assertion that
# replaces the fold.
#
# WHAT THIS PHASE NEEDS OF PHASES 7, 8 AND 9, and none of it can be a `uses` line,
# packages.sh refusing one inside a package: `:read` was one of the six EX_XFILE
# rows and phase 7 took it; four more went with the :edit family in phase 8, which
# is why :file is the LAST and part D exists at all; and `set_rw_fname` was
# `setfname`'s second caller and went with `readfile` in phase 9, which is what
# leaves `rename_buffer` as its only one.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, as every zero edit since phase 2 does, and the source goes with it as
# $state/old.c.  The check needs both: `:file NEWNAME` is the one thing that proves
# the old binary could name a buffer at all, and no recording can see it.
set -eu

work=${1:?usage: zero10-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero10-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero10 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  noname       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  noname       the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: :file NEWNAME is the only evidence the old binary could name a buffer at all, and no recording can see it"

# tools/phaserun.sh sweeps next, then runs pipes/zero10-check.sh.
