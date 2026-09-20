#!/bin/sh
# Whim phase 65 -- no rot13, no operator function, no empty key handler.
# See WHIM-GOAL.md.
#
# Usage: pipes/whim65-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Three cuts, and only the first changes what the editor can do:
#
#   ROT13  g?, the one operator here that encodes rather than edits.  It goes
#       whole: nv_g_cmd()'s case, the OP_ROT13 dispatch label, nv_search()'s
#       redirect -- which is how `g?` reaches the operator when a search is
#       pending -- and swapchar()'s three arms, after which swapchar() is the
#       case-changing function it always really was.
#   THE OPERATOR FUNCTION  g@, which has had nothing to call since the eval
#       feature went: op_function() is one emsg(), and 'operatorfunc' does not
#       exist to name a function anyway.  The dispatch, the OP_FUNCTION term in
#       the motion_force test, and op_function() itself all go.
#   AN EMPTY CALL  ins_ctrl_x() has an empty body -- CTRL-X in Insert mode began
#       a completion, and completion went in phase 6.  The key stays inert, but
#       it no longer calls a function to do nothing.
#
# WHAT IS DELIBERATELY KEPT, because "does nothing" and "should be deleted" are
# different claims:
#
#   CTRL-P and CTRL-N in Insert mode are `break;` -- they do nothing on purpose.
#       Deleting the labels would drop them into `normalchar`, which INSERTS the
#       control character, so removing dead-looking code would add behaviour.
#   zy, zp and zP are live.  It looks as though `zy` must reach
#       internal_error("get_op_type()"), since opchars[] has no {'z','y'} row --
#       but get_op_type() special-cases 'z'+'y' to OP_YANK before it consults the
#       table.  Measured on the q64 binary: no error, no message.
#   The opchars[] rows for g? and g@ stay.  The table is positional -- a row's
#       index IS its OP_* value -- so removing one renumbers every operator after
#       it.  Nothing reaches them once nv_g_cmd() has no case.
#
# THE DELTA: no Ex command, and no behaviour case -- the harness never rot13s.
# The probes check g?g? no longer encodes, that g?? and ?-with-operator-pending
# do not either, that g@g@ is refused, and that gu/gU/g~ still work, since they
# share swapchar() with the arms that go.
set -eu

work=${1:?usage: whim65-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim65 "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim65-check.sh.
