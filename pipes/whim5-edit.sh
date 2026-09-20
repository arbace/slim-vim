#!/bin/sh
# Whim phase 5 -- one regexp engine, not two.  See WHIM-GOAL.md.
#
# Usage: pipes/whim5-edit.sh <work-dir> <state-dir>       (run from the repository root)
#
# vim carries two regexp engines and an option to choose between them.  That is
# a MIGRATION PATH -- the NFA engine was new once, and 'regexpengine' existed so
# a user could go back when it misbehaved -- and an embedded fork inherits the
# machinery without inheriting the reason.
#
# This is the first removal here driven by measurement rather than by category.
# 'regexpengine' is compiled in as 1, so nothing this editor does by default
# enters the NFA code, and tools/coverage.sh never reached a line of it across
# the behaviour cases, all 600 Ex commands and the pty scenarios.  It was the
# largest single entry on that list: nfa_emit_equi_class alone is 4,122 lines.
#
# It is NOT unused -- `:set re=2` and `\%#=2` reach it -- so this is a decision,
# and the capability goes knowingly.
#
# Checked before cutting: the custom delimiter atoms this tree's upstream branch
# exists for are implemented in BOTH engines, so the backtracking one keeps them.
#
# THE DELTA: none the harness records.  It never sets 'regexpengine' and never
# writes \%#=, and every pattern it does use is compiled by the same engine as
# before -- which is the point of a default the product never changed.
set -eu

work=${1:?usage: whim5-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the choice, and the option that offered it -----------------------
tools/st.sh nonfa "$f"
tools/st.sh dropoptions "$f" regexpengine

# The sweep cannot finish this one on its own, and that is the phase's real
# lesson.  With the entry points cut, six thousand lines of NFA engine are
# reachable from nothing -- and every function in it is MENTIONED by another
# function in it, so -Wall, which counts references, sees nothing wrong.  A
# recursive-descent parser and a mutually recursive matcher are both immune to
# reference counting by construction.
#
# `funcreach` is typereach.py's argument applied to functions:
# reachability from roots, not reference counts.  It found 29 functions holding
# 4,195 lines, every one of them in the regexp_nfa.c region -- including seven
# that do not carry the prefix and would have been missed by any rule based on
# the name.
tools/st.sh funcreach "$f" --delete

# tools/phaserun.sh sweeps next, then runs pipes/whim5-check.sh.
