#!/bin/sh
# Whim phase 77 -- no buffer-name argument matching.  See WHIM-GOAL.md.
#
# Usage: pipes/whim77-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# do_one_cmd() computes, at 20635,
#
#     ni = (!(cmdidx < 0) && (cmd_func == ex_ni || cmd_func == ex_script_ni))
#
# -- "this command is not implemented" -- and SEVEN later checks consult it before
# doing work.  One does not: the EX_BUFNAME pre-dispatch block, guarded only by
# `!(cmdidx < 0)`, which compiles a regexp and matches it against the buffer to turn
# `:buffer foo` into a line number.
#
# Every command carrying EX_BUFNAME is ex_ni: :buffer, :bdelete, :bunload, :bwipeout,
# :checktime, :sbuffer.  So that block does real pattern-matching work for commands
# that cannot succeed, and its result is discarded when the handler errors.
#
# THE EDIT IS A FOLD, NOT A GUARD.  Adding `&& !ni` would leave a block that can
# still never run -- dead weight wearing a condition.  The condition is false for
# every command that reaches it, so fold_never removes it outright, and
# buflist_findpat loses its only caller.
#
# WHAT GOES BY CASCADE: buflist_findpat (71 lines), file_pat_to_reg_pat (167) and
# buflist_match (13) -- 251 lines whose whole purpose was naming a buffer by pattern.
# Nothing here deletes them by name; removing the one call site orphans them and the
# sweep takes them.
#
# THE BLOCK CONTAINS `goto doend;` AND THAT IS SAFE.  doend is do_one_cmd's shared
# exit label, targeted from many other places, so this removes a goto STATEMENT, not
# a label -- the distinction that mattered for readfile's `theend` in phase 75 and
# for close_buffer's `aucmd_abort`, where the label itself was inside the fold.
#
# THE DELTA: none expected.  `:buffer foo` already exits 1 with nothing on stderr --
# ex_ni sets eap->errmsg rather than printing, and an exsweep row is
# `exit= left= err=`.  Measured on q76: exit=1, stderr empty, file written.  So the
# gain here is code, not behaviour.  Declared empty, left for whimdelta.sh.
set -eu

work=${1:?usage: whim77-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim77 "$f"

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim77-check.sh.
