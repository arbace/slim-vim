#!/bin/sh
# Whim phase 32 -- insert completion, the popup menu, and the keys that reached
# them.  See WHIM-GOAL.md.
#
# Usage: pipes/whim32-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# CTRL-N and CTRL-P complete the word being typed, and CTRL-X opens a submenu of
# sources: the current file, 'dictionary', 'thesaurus', tags, file names,
# spelling, whole lines, the command line, a register, a user function.  Almost
# none of those still exists -- tags went in phase 10, spelling was never in a
# tiny build, 'completefunc' needs +eval, and file-name completion goes through
# the globbing phase 7 removed.
#
# TWO CUTS, AND THE SWEEP BETWEEN THEM.  First the predicates: nine functions
# completion is entered through become constants, and the sweep takes the
# sources and the display behind them.  That makes completion PRODUCE NOTHING,
# and it does not remove the state machine -- seventy functions stay reachable,
# because edit() calls them directly and the redraw layer asks pum_visible() on
# its own account.  A stub answers a question; it does not remove the caller
# that asks it.  So then the callers: the CTRL-X submode, the per-key completion
# arm, 'autocomplete', the four arrow-key arms and the docomplete label, and the
# second sweep takes the callees.
#
# This was two phases, and the second existed only because the first stopped
# short.  The sweep between the cuts is kept: `nocomplkeys` counts and
# matches text in edit() as the first sweep leaves it, and a count taken over
# code about to be swept is a different count.
#
# THE DELTA: none the harness records.  No behaviour case types CTRL-N and these
# are insert-mode keys, so the phase checks both halves itself, in a pty:
# completion must be absent, and insert mode must still insert.
set -eu

work=${1:?usage: whim32-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- the predicates, and the options only completion read ------------------
tools/st.sh nocompl "$f"
tools/st.sh dropoptions "$f" --local \
    autocomplete complete completefunc completeopt dictionary infercase \
    pumborder pummaxwidth pumopt \
    pumheight pumwidth thesaurus

tools/sweep.sh "$f"

# --- the callers, and the buffer fields those options had ------------------
tools/st.sh droplocal "$f" b_p_cpt b_p_cot b_p_dict b_p_tsr b_p_inf b_p_ac
tools/st.sh nocomplkeys "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim32-check.sh.
