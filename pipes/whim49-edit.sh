#!/bin/sh
# Whim phase 49 -- one set of options.  See WHIM-GOAL.md.
#
# Usage: pipes/whim49-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Every buffer and window option keeps its global and local copy inside the
# editor; what goes is every way to make the two differ, so :set is the only way
# an option is given a value.  :setlocal and :setglobal go, the :set opt< suffix
# goes, and modelines go with their four options: 'modeline', 'modelines',
# 'modelineexpr' and 'modelinestrict'.  See `oneoptset`.
#
# THE DELTA: :setlocal and :setglobal, which succeeded run bare.
set -eu

work=${1:?usage: whim49-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh retire "$f" setlocal setglobal
tools/st.sh oneoptset "$f"
# The rows go before the sweep and without --strict: do_modelines() reads
# 'modeline' and 'modelines' until the sweep takes it.  The post-condition is the
# check.
tools/st.sh dropoptions "$f" --local modeline
tools/st.sh dropoptions "$f" modelines modelineexpr modelinestrict

tools/sweep.sh "$f"
tools/st.sh droplocal "$f" b_p_ml

# tools/phaserun.sh sweeps next, then runs pipes/whim49-check.sh.
