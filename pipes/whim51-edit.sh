#!/bin/sh
# Whim phase 51 -- a byte that is not UTF-8 is kept as it is.  See WHIM-GOAL.md.
#
# Usage: pipes/whim51-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Since Phase 12 an invalid byte was read as '?', the buffer made read-only, and
# a forced :w wrote the '?'.  Now the byte is kept, shown as <ff>, written back
# unchanged, and the buffer stays writable; "[ILLEGAL BYTE in line N]" is still
# reported.  ++bad goes, since keeping is the only behaviour left.  See
# `keepbytes`.
#
# THE DELTA: none the harnesses record -- no case has an invalid byte.  The probe
# below is the check, against what Phase 12 did.
set -eu

work=${1:?usage: whim51-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh keepbytes "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim51-check.sh.
