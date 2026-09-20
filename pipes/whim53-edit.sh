#!/bin/sh
# Whim phase 53 -- no conversion layer, no 'encoding'.  See WHIM-GOAL.md.
#
# Usage: pipes/whim53-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# ++enc and the help-buffer branch were the last ways into readfile()'s and
# buf_write()'s conversion; with them gone everything behind folds.  'encoding'
# goes, the mb_* function pointers become direct calls to the UTF-8
# implementations, and the ++ff, ++enc and ++bad completion left behind goes.
# See `noconv`.
#
# THE DELTA: none the harnesses record.  The probes check ++enc and :set enc are
# refused and that UTF-8 editing and a kept invalid byte are unchanged.
set -eu

work=${1:?usage: whim53-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh noconv "$f"
# The row goes before the sweep and without --strict: did_set_encoding() and the
# conversion helpers read p_enc until the sweep takes them.  The post-condition
# below is the check -- and mb_init() no longer reads it, which is what makes the
# drop safe at all.
tools/st.sh dropoptions "$f" encoding
# 'makeencoding' converted :make output, and :make went long ago; what reads it is
# plumbing.  The row first, then its buffer field once the sweep has run.
tools/st.sh dropoptions "$f" --local makeencoding

tools/sweep.sh "$f"
tools/st.sh droplocal "$f" b_p_menc

# tools/phaserun.sh sweeps next, then runs pipes/whim53-check.sh.
