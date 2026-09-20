#!/bin/sh
# Zero phase 13 -- no `FILE *` that is never opened.  See ZERO-GOAL.md.
#
# Usage: pipes/zero13-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# Two `static FILE *` survive in this editor and NOTHING HAS EVER OPENED EITHER OF
# THEM IN ANY BUILD OF zero-vim: `scriptin[NSCRIPT]`, which `-s {scriptfile}` filled
# and which whim removed the option for, and `redir_fd`, which `:redir > file` filled
# and which whim removed the command for.  So this phase removes the POSSIBILITY
# rather than a behaviour -- the same situation as phase 9, and the same answer:
# nothing it takes is reachable, the declared delta is nothing at all, and the
# evidence is an instrumented pair and a set of counts.
#
# THE COUNTS ARE THE ARGUMENT, and each is asserted before anything is folded:
#
#   * `scriptin[]` is assigned in exactly ONE place in the whole file, and that place
#     is `scriptin[curscript] = NULL;` inside `closescript()`.  So it is NULL for
#     ever, `== NULL` is TRUE and `!= NULL` is FALSE at every site.
#   * `redir_fd`'s only assignment is its own declaration, `= NULL`.  Same.
#   * `ui_write()` has three mentions -- a prototype, a definition and ONE call --
#     and that call passes `FALSE` for `console`.
#
# SIX ANCHORS, in three groups.
#
#   A  scriptin[] is NULL for ever.
#      1  `may_sync_undo()` loses one conjunct and SURVIVES: `u_sync()` still runs on
#         the same condition.
#      2  `is_safe_now()` loses one conjunct and SURVIVES.
#      3  `using_script()` is FALSE at both call sites -- a `&& !using_script()`
#         conjunct and a `|| using_script()` disjunct -- and the sweep then takes it.
#      4  `inchar()`'s script reader, deleted as TEXT with its local, after which
#         `if (script_char < 0)` is always true and folds.  THAT FOLD IS WHAT TAKES
#         `closescript()`'s only caller, and `fclose` and `getc` with it.
#   B  redir_fd is NULL for ever, so `redirecting()` is FALSE always and folds at
#      BOTH call sites.  Their indentation differs, which is what makes two separate
#      one-count patterns honest rather than a count of two over one pattern.
#   C  `ui_write()`'s `console` is FALSE at its one call site, so the `vim_fsync(1)`
#      it guards can never be entered.  THE PARAMETER GOES TOO, and that is what
#      makes the cut honest: leaving it would leave `__attribute__((unused))` on
#      something that will never be read again, which is phase 2's argument for
#      `check_tty(void)` -- and tools/sweep.sh compiles with -Wno-unused-parameter,
#      so an unused parameter is invisible where an unused local is not.
#
# TWO LOCALS ARE FOLDED BY HAND AND NO TOOL COVERS EITHER.
#
#   `retesc` is `FALSE` at its declaration, is written only inside the loop anchor A4
#   deletes, and is read once.  Afterwards it is a local that is READ AND NEVER
#   WRITTEN: gcc has no warning for that, tools/deadsweep.py acts on warnings, and
#   leaving it would mean `inchar()` returns an uninitialised value on a path the
#   compiler thinks exists.  `return retesc;` becomes `return FALSE;` and the
#   declaration goes.  This is phase 7's `usefilter` judgement in this phase's shape.
#
#   `did_return` is the same shape one level down: the `if (!did_return)` block the
#   redir_write extra removes is its only reader, and an `if` with an empty body is
#   not something any tool here removes either, so the block goes whole with
#   cutil.drop_if and the variable's two lines go with it.
#
# THE RECOMMENDED EXTRA IS TAKEN: `redir_write()` IS A NO-OP AFTERWARDS.  After B it
# is `{ char_u *s = str; static int cur_col = 0; if (redir_off) return; }` -- the
# sweep takes the two variables and leaves a function with five callers that cannot
# do anything.  Leaving it is the "concept the table has and the code does not" that
# whim's Phase 18 argued against, so it goes with its five call sites, and
# `redir_off` -- then written five times and read never, a file-scope static no
# warning covers -- goes with them.
#
# A SECOND EXTRA IS DECLINED AND IS A QUESTION FOR THE USER, not an oversight.  After
# this phase `typedef struct stat stat_T;` has no user and `#include <sys/stat.h>`
# and `#include <fcntl.h>` are needed by nothing.  Removing all three is free -- it
# was measured: same binary, byte-identical recording -- but it would be the FIRST
# TIME ANY ZERO PHASE CHANGES THE DIRECTIVE COUNT, and ZERO-GOAL.md's charter says
# `zero-vim.c` "inherits 18 directives from `whim-vim.c`".  That sentence is a
# statement about the pipeline, so the change belongs to whoever decides it, either
# here or as an includes phase of its own.  The count stays 18.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, and the source goes with it as $state/old.c.  The check needs both: there is
# no behavioural probe this phase can offer, so it instruments the source it was
# HANDED at five places and requires zero markers, with a control that must fire.
set -eu

work=${1:?usage: zero13-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero13-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero13 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  nofile       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  nofile       the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: nothing this phase removes is reachable, so the check instruments THAT source at five places and requires zero markers, with a control that must fire"

# tools/phaserun.sh sweeps next, then runs pipes/zero13-check.sh.
