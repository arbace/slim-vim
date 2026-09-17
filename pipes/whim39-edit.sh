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
# modifier and stays.  See tools/nowindows.py for what a row cannot remove.
#
# THE DELTA: the twenty-seven rows that succeeded run bare, read from the slim
# baseline.  close, hide, sbmodified, wincmd and windo already failed.
set -eu

work=${1:?usage: whim39-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 tools/retire.py "$f" split vsplit new vnew sview close only resize wincmd \
    windo syncbind hide sbuffer sbNext sball sbfirst sblast sbmodified sbnext \
    sbprevious sbrewind ball unhide sunhide aboveleft leftabove belowright \
    rightbelow topleft botright vertical horizontal
python3 tools/nowindows.py "$f"
# These rows go BEFORE the sweep and without --strict -- each one's own callback
# reads its global (did_set_switchbuf, did_set_scrollopt, did_set_cedit,
# did_set_scrollbind), so while the row stands the reader is live.  The
# post-condition below is the check.
python3 tools/dropoptions.py "$f" switchbuf scrollopt cmdwinheight cedit
python3 tools/dropoptions.py "$f" --local scrollbind cursorbind winfixbuf

tools/sweep.sh "$f"
python3 tools/dropoptions.py "$f" --strict previewheight
python3 tools/dropoptions.py "$f" --strict --local previewwindow

# tools/phaserun.sh sweeps next, then runs pipes/whim39-check.sh.
