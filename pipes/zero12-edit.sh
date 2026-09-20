#!/bin/sh
# Zero phase 12 -- the options nothing reads.  See ZERO-GOAL.md.
#
# Usage: pipes/zero12-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# Phases 6 to 11 took every way to reach a file and then the refusal that guarded
# the text.  What they left behind is a set of SETTINGS: `options[]` rows whose
# global nothing reads any more, so that `:set fsync?` answers a question about
# machinery that is not there.  An option that cannot do anything is a lie, and the
# same argument that removed `:write` removes `'write'`.
#
# WHICH ROWS GO IS COMPUTED, NOT LISTED.  The edit walks `options[]`, finds each
# row's `(char_u *)&p_xx` and counts readers of that global outside the row, with
# `dropoptions --strict`'s own exclusions -- another row, the row's `var`
# field, the variable's own declaration, and taking the address, which is an
# identity test and not a dereference.  Exactly SEVEN of the 114 rows have no
# reader, and the program requires that set rather than naming six of them:
#
#   fsync       p_fs       PV_BOTH   goes, but needs droplocal.py b_p_fs first
#   modified    p_mod      PV_BUF    STAYS -- see below
#   prompt      p_prompt   PV_NONE   goes
#   readonly    p_ro       PV_BUF    goes, by ZERO-PLAN.md decision 5
#   undoreload  p_ur       PV_NONE   goes
#   write       p_write    PV_NONE   goes
#   writeany    p_wa       PV_NONE   goes
#
# `'modified'` HAS NO READER OF `p_mod` EITHER AND MUST NOT GO.  ZERO-PLAN.md
# decision 5 keeps it: the state it reports lives in `b_changed`, not in `p_mod`, so
# `:set modified?` answers correctly and the row is not a lie.  A computation that
# took "no reader" as the criterion would delete it, which is why the seven are
# computed and the six are chosen.  `dropoptions` refuses it anyway, on the
# PV_ guard.
#
# `'paste'` IS EXEMPT FOR EVER, and this is the comment that says so -- ZERO-PLAN.md
# 2d and decision 8, the user's standing promise.  `p_paste` has 12 mentions here and
# has them afterwards, and its five save slots `p_ai_nopaste p_et_nopaste
# p_sts_nopaste p_tw_nopaste p_wm_nopaste` are the non-pointer orphans
# `orphanopts` reports and tolerates, before and after, identically.  THE NEXT
# PERSON TO RUN THE COMPUTATION MUST NOT "FIX" THEM.  `+{command}` is likewise
# untouched, for the same promise.
#
# FOUR PARTS.  A and B are the tools' work; C is the only live code here.
#
#   A  the four clean rows, `dropoptions --strict prompt undoreload write
#      writeany`.  The sweep then takes the four globals as -Wunused-variable.
#   B  `'fsync'`, which --strict alone REFUSES -- not on a reader but on the PV_
#      guard, because the row is what initialises the global ('tagcase' taught that
#      by segfaulting before the first keystroke).  `droplocal.py b_p_fs` is the
#      other half and goes first: six plumbing sites, including get_varp()'s two-line
#      "local if set" form.  Then `--strict --local fsync`.
#   C  `'readonly'`, which is LIVE CODE and not an inert row.  `p_ro` the global has
#      had no reader since whim; what survives is the buffer-local `b_p_ro`, and
#      since phase 6 nothing but `:set ro` can set it -- decision 5's premise.  Five
#      edits, in this order and for this reason:
#        1  the W10 warning.  `change_warning()` and its six call sites, each one
#           statement on a line of its own.  There is NO PROTOTYPE -- it is defined
#           above its first call -- so a program that removes one fails loudly.  This
#           also takes the `ui_delay(1002L, TRUE)` that ZERO-GOAL.md phase 2 named as
#           one of the eight other pauses.
#        2  the `[RO]` in `fileinfo()`.  THE FORMAT STRING AND THE ARGUMENT MOVE
#           TOGETHER -- `%s%s%s%s%s%s` to `%s%s%s%s%s` -- and nothing in the build
#           checks a vim_snprintf_safelen count.
#        3  the `[RO]` on the status line, in `win_redr_status()`: the name-padding
#           disjunct and the block that appends it.
#        4  `did_set_readonly()`, BY NAME and with the reason: it is the row's
#           callback and the row is its only other reference, but droplocal.py runs
#           in the same edit and would otherwise find it still reading `b_p_ro`.
#           Measured without it: `droplocal: b_p_ro still has 1 mentions after the
#           plumbing went`, which is the tool working.  The alternative is an inner
#           sweep; this is cheaper and honest.
#        5  the row, then `droplocal.py b_p_ro` -- three plumbing sites.
#
# WHAT THE SWEEP THEN FINDS: `SHM_RO`, `BV_FS`, `BV_RO`, the static string
# `w_readonly` inside change_warning(), the `b_did_warn` field -- which becomes dead
# only after BOTH change_warning and did_set_readonly have gone, so removing one and
# not the other leaves a field with one reader and one writer that no tool reports --
# and the six globals.
#
# THE FLAG LETTERS ARE NOT TOUCHED, AND THAT IS A DECISION.  `'cpoptions'` and
# `'shortmess'` each have a validity list that is a separate string literal from the
# value, so removing a letter from a list cannot move `:set cpo?` or `:set shm?`.
# But `:set shm=F` is accepted silently and `:set shm=y` answers E539, and dropping a
# letter from the list turns the first into the second -- a behaviour change no
# corpus case, Ex row, argv row or pty scenario can see, which is exactly what
# ZERO-GOAL.md rule 2 exists to prevent.  Accepting a letter that does nothing is
# what upstream does for every feature a build lacks.  Measured: 23 of 'cpoptions'
# 60 letters and 14 of 'shortmess' 23 are inert here, and THIS PHASE MAKES EXACTLY
# ONE MORE SO -- `'shortmess'`'s `r`, whose SHM_RO the sweep takes with the `[RO]`
# indicator.  The check asserts both literals character for character.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, as every zero edit since phase 2 does, and the source goes with it as
# $state/old.c.  The check needs both, and needs them more than any phase so far:
# THIS PHASE DECLARES NOTHING, because `:set` is the one thing zero's instrument
# cannot read, and the probes are the whole evidence.
set -eu

work=${1:?usage: zero12-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero12-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero12 "$f"

# ---- A. the four clean rows ----------------------------------------------------------
# --strict is the guard: it refuses a row while anything still reads its global,
# because the row is what INITIALISES that global.  The sweep takes the four
# variables afterwards as -Wunused-variable.
tools/st.sh dropoptions "$f" --strict prompt undoreload write writeany

# ---- B. 'fsync', where --strict alone is NOT the guard --------------------------------
# The row is PV_BOTH + PV_BUF + BV_FS, so dropoptions stops on the PV_ guard before
# the reader test is ever reached, and its message talks about a segfault at startup
# rather than about readers.  droplocal.py is the other half and goes first.
tools/st.sh droplocal "$f" b_p_fs
tools/st.sh dropoptions "$f" --strict --local fsync

# ---- C5. 'readonly': the row, then the field -------------------------------------------
tools/st.sh dropoptions "$f" --strict --local readonly
tools/st.sh droplocal "$f" b_p_ro

tools/st.sh edit zero12rows "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  noopts       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  noopts       the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: this phase declares nothing, because :set is the one thing zero's instrument cannot read, and the probes are the whole evidence"

# tools/phaserun.sh sweeps next, then runs pipes/zero12-check.sh.
