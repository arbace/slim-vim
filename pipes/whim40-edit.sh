#!/bin/sh
# Whim phase 40 -- no window sizes to set.  See WHIM-GOAL.md.
#
# Usage: pipes/whim40-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# With one window there is nothing for 'winheight', 'winminheight', 'winwidth',
# 'winminwidth', 'helpheight', 'splitbelow', 'splitright', 'splitkeep',
# 'equalalways', 'eadirection', 'winfixheight' or 'winfixwidth' to decide.  The
# rows go.  The frame arithmetic that aucmd_prepbuf() still runs keeps reading
# the globals, so each keeps its default as an initialiser -- see
# `nowinsizes`.
#
# THE DELTA: none the Ex sweep records beyond Phase 39's -- no row is retired.
# :set of any of these names is refused now, which the probe below checks.
set -eu

work=${1:?usage: whim40-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh nowinsizes "$f"
# Every row goes before the sweep and without --strict: the globals are read by
# live code on purpose now, and each row's callback reads its own.  orphanopts,
# in the delta below, is what proves each survivor has an initialiser.
tools/st.sh dropoptions "$f" splitbelow splitright splitkeep equalalways \
    eadirection winheight winminheight winwidth winminwidth helpheight
tools/st.sh dropoptions "$f" --local winfixheight winfixwidth

# tools/phaserun.sh sweeps next, then runs pipes/whim40-check.sh.
