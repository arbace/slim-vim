#!/bin/sh
# Whim phase 57 -- no lisp.  See WHIM-GOAL.md.
#
# Usage: pipes/whim57-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# 'lisp' and 'lispwords' go, and with them everything they switched on:
# get_lisp_indent() for autoindent, =, gq and new lines; lisp_match() over
# 'lispwords'; '-' as a keyword character; ';' line comments in check_linecomment();
# and findmatchlimit()'s lisp mode, which stopped % at a ';' comment and skipped
# #\( and #\[ character literals.  'lispoptions' went in Phase 55.
#
# b_p_lisp is folded as FALSE at every reader rather than stubbed, so each branch
# it guarded is either gone or taken unconditionally.
#
# THE DELTA: none the harnesses record -- no case sets 'lisp'.  The probes check
# the two options are unknown and that % still matches across a ';'.
set -eu

work=${1:?usage: whim57-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim57 "$f"

tools/st.sh dropoptions "$f" --local lisp lispwords

tools/sweep.sh "$f"
tools/st.sh droplocal "$f" b_p_lisp b_p_lw

# tools/phaserun.sh sweeps next, then runs pipes/whim57-check.sh.
