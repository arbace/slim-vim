#!/bin/sh
# Whim phase 60 -- no suffix, case, delay, verbose-file, debug or filter-program options.  See WHIM-GOAL.md.
#
# Usage: pipes/whim60-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Seven options whose default is the only value anything could still act on:
#
#   'suffixes'           ordered wildcard matches, and wildcards have not expanded
#                        since Phase 7 removed globbing; match_suffix() goes
#   'fileignorecase'     off: its five tests fold as false
#   'autocompletedelay'  0: inchar_loop()'s delay is never pending
#   'verbosefile'        empty: the file is never opened, so redir_write(),
#                        redirecting() and the verbose_enter/leave family fold
#   'debug'              empty: emsg_not_now(), emsg_core() and vim_beep() fold
#   'formatprg'          gq through an external program: it only built a
#   'equalprg'           :{range}!prg line, and :! has been ex_ni since Phase 44.
#                        gq and = always take the internal path now.
#
# THE DELTA: none the harnesses record.  The probes check the seven are unknown
# and that gq still formats.
set -eu

work=${1:?usage: whim60-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim60 "$f"

tools/st.sh dropoptions "$f" suffixes fileignorecase autocompletedelay verbosefile debug
tools/st.sh dropoptions "$f" --local formatprg equalprg

tools/sweep.sh "$f"
# get_varp()'s "local if set" case for 'equalprg' is written &curbuf->b_p_ep, without
# the parentheses droplocal.py matches -- the same gap as 'keywordprg' in Phase 56.
tools/st.sh edit whim60ep "$f"
tools/st.sh droplocal "$f" b_p_fp b_p_ep

# tools/phaserun.sh sweeps next, then runs pipes/whim60-check.sh.
