#!/bin/sh
# Whim phase 55 -- no option nothing reads.  See WHIM-GOAL.md.
#
# Usage: pipes/whim55-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Phase 54 took the options with no variable.  These have one, and nothing but
# the option machinery reads it: the declaration, the row, get_varp() and the
# buffer copy for a local one, set_context_in_set_cmd()'s completion, and a
# did_set_* callback that only validates the value or fills a flag set nothing
# reads (cfc_flags, cia_flags, opfunc_cb).  Setting one of them changed nothing.
#
#   autocompletetimeout cdhome cdpath completetimeout imcmdline secure
#   shellcmdflag shelltemp shellxescape shellxquote shortname ttybuiltin warn
#   xtermcodes commentstring completefuzzycollect completeitemalign helpfile
#   lispoptions operatorfunc
#
# And sixteen terminal codes the editor stores and never sends:
#
#   t_8b t_8f t_EC t_EI t_GP t_RB t_RC t_RF t_RS t_SC t_SH t_SI t_SR t_WP t_XM t_u7
#
# Their KS_ enumerators stay: the built-in terminal tables still name them.
#
# FOUND, NOT LISTED FROM MEMORY: each was checked for a reader outside that
# machinery by its variable (p_xx, b_p_xx, wo_xx, KS_xx), for a by-name use of
# its long or short name, and for what its callback assigns.  The post-greps
# below are the same check, and a new reader of any of them fails the phase.
#
# THE DELTA: none the harnesses record -- no case sets one.  The probes check
# three of them are now unknown.
set -eu

work=${1:?usage: whim55-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim55 "$f"

tools/st.sh dropoptions "$f" autocompletetimeout cdhome cdpath completetimeout imcmdline secure \
    shellcmdflag shelltemp shellxescape shellxquote ttybuiltin warn xtermcodes \
    completefuzzycollect completeitemalign helpfile operatorfunc \
    t_8b t_8f t_EC t_EI t_GP t_RB t_RC t_RF t_RS t_SC t_SH t_SI t_SR t_WP t_XM t_u7
tools/st.sh dropoptions "$f" --local shortname commentstring lispoptions

# No sweep here.  One stood here, and the lines after it were written for swept text,
# but this phase and every stage it has run in reproduce their boundaries without
# it (WHIM-PLAN.md 2c; pipes/whim.stages) -- the stage's one sweep does its work.
tools/st.sh droplocal "$f" b_p_sn b_p_cms b_p_lop

# tools/phaserun.sh sweeps next, then runs pipes/whim55-check.sh.
