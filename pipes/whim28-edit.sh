#!/bin/sh
# Whim phase 28 -- C indenting.  See WHIM-GOAL.md.
#
# Usage: pipes/whim28-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# get_c_indent() is 1,534 lines and the largest function left in the file: a
# model of C syntax built to answer one question, how far to indent this line.
# With in_cinkeys() and the cin_* helpers it comes to 3,007 lines.
#
# 'autoindent' stays -- it is on by default here -- and copies the previous
# line's indent, which is what an embedded editor needs.  'lisp' and
# 'indentexpr' are different indenters and are not touched.
#
# FIVE OPTIONS, ALL PV_BUF, so the rows go with --local and the buffer fields
# with droplocal.py afterwards, in that order: the option callbacks read the
# field, so the sweep that removes them has to run in between.
#
# THE DELTA: none the harness records.  Four behaviour cases exercise indenting
# and all four are 'autoindent' and 'formatoptions', not 'cindent' -- the phase
# checks that directly, by indenting a C fragment and requiring the result the
# line above gives rather than the one C syntax would.
set -eu

work=${1:?usage: whim28-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh nocindent "$f"
# --local WITHOUT --strict, which phase 16 settled: the global-read guard runs
# before droplocal.py, and the reader it finds -- `buf->b_p_cin = p_cin;` -- is
# the buffer-copy plumbing droplocal owns.  The post-sweep greps below are the
# check instead.
tools/st.sh dropoptions "$f" --local \
    cindent cinkeys cinoptions cinscopedecls cinwords

tools/sweep.sh "$f"
tools/st.sh droplocal "$f" b_p_cin b_p_cink b_p_cino b_p_cinsd b_p_cinw

# tools/phaserun.sh sweeps next, then runs pipes/whim28-check.sh.
