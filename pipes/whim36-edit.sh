#!/bin/sh
# Whim phase 36 -- one tab page, always.  See WHIM-GOAL.md.
#
# Usage: pipes/whim36-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# A tab page is a set of windows the editor can switch between whole.  The
# tab-page list is still the container every window lives in, so it stays with
# exactly one entry, and every way to make or reach a second goes: the fifteen
# rows, the :tab modifier, the tab branches of the handlers the tab commands
# shared, gt/gT/g<Tab>, CTRL-PageUp/PageDown, CTRL-W T/gt/gT/g<Tab>/gf, the tab
# line, and 'showtabline', 'tabline', 'tabpagemax' and 'tabclose'.  Each key keeps
# the answer it already gave with one tab page.  See `notabs`.
#
# THE DELTA: the thirteen rows that succeeded run bare -- :tab, :tabedit,
# :tabfirst, :tabmove, :tablast, :tabnext, :tabnew, :tabonly, :tabprevious,
# :tabNext, :tabrewind, :tabs and :redrawtabline -- measured before the cut.
# :tabclose and :tabdo already failed with no argument.  No harness opens a tab
# page.
set -eu

work=${1:?usage: whim36-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- the rows, then what a row cannot reach ---------------------------------
tools/st.sh retire "$f" tab tabclose tabdo tabedit tabfirst tabmove tablast \
    tabnext tabnew tabonly tabprevious tabNext tabrewind tabs redrawtabline
tools/st.sh notabs "$f"
# 'tabclose' goes BEFORE the sweep and without --strict: its own callback,
# did_set_tabclose(), reads p_tcl, so while the row stands the reader is live and
# the sweep cannot take it.  The post-condition below is the check -- after the
# sweep nothing names p_tcl or tcl_flags.
tools/st.sh dropoptions "$f" tabclose

# No sweep here.  One stood here, and the lines after it were written for swept text,
# but this phase and every stage it has run in reproduce their boundaries without
# it (WHIM-PLAN.md 2c; pipes/whim.stages) -- the stage's one sweep does its work.
tools/st.sh dropoptions "$f" --strict showtabline tabline tabpagemax

# tools/phaserun.sh sweeps next, then runs pipes/whim36-check.sh.
