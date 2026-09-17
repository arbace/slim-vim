#!/bin/sh
# Whim phase 49 -- one set of options.  See WHIM-GOAL.md.
#
# Usage: pipes/whim49-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Every buffer and window option keeps its global and local copy inside the
# editor; what goes is every way to make the two differ, so :set is the only way
# an option is given a value.  :setlocal and :setglobal go, the :set opt< suffix
# goes, and modelines go with their four options: 'modeline', 'modelines',
# 'modelineexpr' and 'modelinestrict'.  See tools/oneoptset.py.
#
# THE DELTA: :setlocal and :setglobal, which succeeded run bare.
set -eu

work=${1:?usage: whim49-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 tools/retire.py "$f" setlocal setglobal
python3 tools/oneoptset.py "$f"
# The rows go before the sweep and without --strict: do_modelines() reads
# 'modeline' and 'modelines' until the sweep takes it.  The post-condition is the
# check.
python3 tools/dropoptions.py "$f" --local modeline
python3 tools/dropoptions.py "$f" modelines modelineexpr modelinestrict

tools/sweep.sh "$f"
python3 tools/droplocal.py "$f" b_p_ml

# tools/phaserun.sh sweeps next, then runs pipes/whim49-check.sh.
