#!/bin/sh
# Whim phase 42 -- one buffer, always.  See WHIM-GOAL.md.
#
# Usage: pipes/whim42-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Editing another file reuses the one buffer: do_ecmd() wipes the buffer it
# leaves, nothing is hidden, and there is no alternate file.  :e, :enew, :next,
# :previous, :drop, :saveas, :file and gf keep working; a file left behind takes
# its undo history, marks and local options with it.  Three rows go:
#
#   bnext bprevious keepalt
#
# plus the :hide and :keepalt modifiers, CTRL-^, and 'hidden' and 'bufhidden'.
# :qall, :wall, :wqall and :xall stay: with one buffer they are :q and :w, and
# every harness here quits with :qa!.  'buflisted' stays too -- its field is
# internal state the buffer code reads, not only an option.  No command-line
# option opened more than one buffer.  See tools/onebuffer.py.
#
# THE DELTA: bnext, bprevious and keepalt, which succeeded run bare.
set -eu

work=${1:?usage: whim42-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 tools/retire.py "$f" bnext bprevious keepalt
python3 tools/onebuffer.py "$f"
# 'hidden' is read by buf_hide(), which the folds above leave with no caller but
# the sweep has not taken yet; 'bufhidden' by its own callback.  Both rows go
# before the sweep, and the post-condition is the check.
python3 tools/dropoptions.py "$f" hidden
python3 tools/dropoptions.py "$f" --local bufhidden

tools/sweep.sh "$f"
python3 tools/droplocal.py "$f" b_p_bh

# tools/phaserun.sh sweeps next, then runs pipes/whim42-check.sh.
