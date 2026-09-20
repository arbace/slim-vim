#!/bin/sh
# Whim phase 69 -- one file argument, and no argument list.  See WHIM-GOAL.md.
#
# Usage: pipes/whim69-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# THE ORDER MATTERS, and it is the opposite of the obvious one.  An earlier
# attempt at "one buffer" imposed reuse inside buflist_new() and deleted the
# argument-list call that reaches it -- and that call is THE ONLY THING THAT NAMES
# THE FIRST BUFFER.  open_buffer() reads through `readfile(curbuf->b_ffname, ...)`,
# so with no name it read nothing: the buffer came up empty, every edit was a
# silent no-op, and :wq wrote the original bytes back.  It built and it passed two
# of three probes.
#
# So this phase limits the command line FIRST and keeps the naming path exactly as
# it is:
#
#   ONE FILE ARGUMENT.  A second non-option argument is mainerr(ME_TOO_MANY_ARGS),
#       which is what vim already answers for a second `-`.  One file means one
#       entry, which is what makes the list pointless rather than merely unused.
#   THE NAME STILL GOES THROUGH buflist_add().  curbuf exists and is unnamed and
#       empty when command_line_scan() runs -- main() calls common_init_2(), which
#       calls win_alloc_first(), before the scan -- so buflist_new() reuses it and
#       sets b_ffname, exactly as today.  Only the LIST around that call goes.
#   THE ARGUMENT LIST.  :next and :previous point at ex_ni; the other 21 argument
#       commands already do.  ex_next(), ex_previous(), do_argfile(), do_arglist(),
#       arglist_del_files(), alist_set(), alist_clear(), alist_add(), alist_name(),
#       editing_arg_idx(), check_arglist_locked(), arg_had_last, global_alist,
#       alist_T, aentry_T, w_alist, w_arg_idx, w_arg_idx_invalid and mparm_T.fname
#       go with them, by fold or by sweep.
#
# WHAT FOLDS BECAUSE THE COUNT IS ALWAYS ONE: check_more(), whose "N more files to
# edit" refusal can never fire; append_arg_number(), the "(N of M)" suffix in
# :file; and the four ADDR_ARGUMENTS arms of Ex range parsing.
#
# THE DELTA: NONE, which was measured rather than assumed.  :next and :previous
# were declared as moving and did not: an exsweep row is `exit= left= err=`, and
# with one file argument do_argfile() already answered "there is only one file to
# edit" -- so pointing the rows at ex_ni changes the message text, which the sweep
# does not record, while the exit status, the files touched and stderr all stay the
# same.  The declaration is narrowed to match the measurement; widening one to fit
# is what whimdelta.sh exists to refuse.
#
# The probes are LOAD-FIRST -- the first one proves the buffer holds the file's
# lines, because that is the check the earlier attempt did not have and needed.
set -eu

work=${1:?usage: whim69-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim69 "$f"

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim69-check.sh.
