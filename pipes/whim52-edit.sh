#!/bin/sh
# Whim phase 52 -- UTF-8 is not a question.  See WHIM-GOAL.md.
#
# Usage: pipes/whim52-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# mb_init() sets enc_utf8, has_mbyte and enc_latin1like TRUE and enc_dbcs and
# enc_unicode 0, every time, since Phase 12.  Some four hundred and fifty tests of
# them fold as constants, never dropping a side effect, and the sweep takes the
# DBCS and latin1 paths nothing reaches.  See `utf8only`.
#
# THE DELTA: none.  Folding a constant changes no behaviour, and the harnesses --
# which include multibyte motion, case and insertion cases -- are the check.
set -eu

work=${1:?usage: whim52-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh utf8only "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim52-check.sh.
