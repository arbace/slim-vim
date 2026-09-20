#!/bin/sh
# Whim phase 43 -- no -c, --cmd, -R, -m, -M or -w.  See WHIM-GOAL.md.
#
# Usage: pipes/whim43-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Each becomes what an unknown option is.  +{command} stays and fills the list
# -c did, which is why the harnesses now pass +{command}: behaviour.py and
# exsweep.py used -c, and give the same result either way against every binary
# either pipeline has produced.  See `nocmdargs`.
#
# THE DELTA: none the Ex sweep records.  No Ex command moves.
set -eu

work=${1:?usage: whim43-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh nocmdargs "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim43-check.sh.
