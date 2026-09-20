#!/bin/sh
# Whim phase 39 -- one window, always.  See WHIM-GOAL.md.
#
# Usage: pipes/whim39-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# The window list stays, with one window in it; everything that makes, reaches,
# resizes, closes or binds a second goes.  Thirty-two rows:
#
#   split vsplit new vnew sview close only resize wincmd windo syncbind hide
#   sbuffer sbNext sball sbfirst sblast sbmodified sbnext sbprevious sbrewind
#   ball unhide sunhide
#   aboveleft leftabove belowright rightbelow topleft botright vertical horizontal
#
# plus CTRL-W, the command-line window (q:, q/, q?, CTRL-F), -o and -O, and the
# options that bind or fix windows or choose how to split.  :hide {cmd} is a
# modifier and stays.  See `nowindows` for what a row cannot remove.
#
# THE DELTA: the twenty-seven rows that succeeded run bare, read from the slim
# baseline.  close, hide, sbmodified, wincmd and windo already failed.
set -eu

work=${1:?usage: whim39-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh retire "$f" split vsplit new vnew sview close only resize wincmd \
    windo syncbind hide sbuffer sbNext sball sbfirst sblast sbmodified sbnext \
    sbprevious sbrewind ball unhide sunhide aboveleft leftabove belowright \
    rightbelow topleft botright vertical horizontal
tools/st.sh nowindows "$f"
# These rows go BEFORE the sweep and without --strict -- each one's own callback
# reads its global (did_set_switchbuf, did_set_scrollopt, did_set_cedit,
# did_set_scrollbind), so while the row stands the reader is live.  The
# post-condition below is the check.
tools/st.sh dropoptions "$f" switchbuf scrollopt cmdwinheight cedit
tools/st.sh dropoptions "$f" --local scrollbind cursorbind winfixbuf

# No sweep here.  One stood here, and the lines after it were written for swept text,
# but this phase and every stage it has run in reproduce their boundaries without
# it (WHIM-PLAN.md 2c; pipes/whim.stages) -- the stage's one sweep does its work.
tools/st.sh dropoptions "$f" --strict previewheight
tools/st.sh dropoptions "$f" --strict --local previewwindow

# tools/phaserun.sh sweeps next, then runs pipes/whim39-check.sh.
