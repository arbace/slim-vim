#!/bin/sh
# Zero phase 24, the check -- the attributes.
# See pipes/zero24-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero24-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero24-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# THIS PHASE CHANGES NO STATEMENT, so there is no behavioural probe to offer and none is
# offered -- no editor is run and nothing is staged.  What it has instead is stronger
# than any recording: THE BINARY IS THE SAME BYTES.  That is tier 1 of CLAUDE.md's
# verification table and it subsumes every screen case, every Ex-command row, every
# command line and every pty scenario at once, because the program that would be run is
# literally the same program.  It is phase 23's shape exactly.
#
# BUT THE BINARY IS ALSO BLIND TO THE ONLY DECISION IN THIS PHASE THAT COULD BE WRONG,
# and that is why there are three more sections.  An attribute emits no code: MEASURED,
# removing all six survivors as well gives a binary that is STILL `cmp`-identical, while
# `-Wformat=2` goes from 115 warnings to zero.  So `cmp` proves the 133 removals and
# respellings were harmless and says NOTHING about the six kept.  The evidence for those
# is the warnings, and it is in section 5.
#
# WHAT IS CLAIMED, in seven parts:
#
#   ARITHMETIC  computed FROM THE INPUT and not written here: the input's attributes
#               partition into unused/fallthrough/format/format_arg, the output holds
#               exactly the format and format_arg ones on lines that are byte-identical
#               to the input's, `[[fallthrough]];` appears once per GNU one, the line
#               count is unchanged and so is the count of doubled spaces before a `,`
#               or `)`.  tools/canon.sh is a NO-OP on the output.
#   PARAMETERS  with `-Wunused-parameter` turned back ON -- the one warning the sweep
#               switches off -- the output warns 92 times more than the input, EVERY
#               one of them `-Wunused-parameter` at a line that carried an attribute,
#               and not one `-Wunused-variable`.  113 sites, 92 warnings: the other 21
#               marked a parameter this build USES, and they are named.
#   FALLTHROUGH `-Wimplicit-fallthrough` is silent on both, and the control is the
#               output with all 20 statements blanked, which must warn 18 times.  The
#               two that do not are named and KEPT: each follows a case label with no
#               statement at all, where C falls through silently and gcc has nothing to
#               diagnose.  Pruning them would be pruning by the compiler's current
#               opinion of a switch, which is not what makes a fallthrough deliberate.
#   C23         `[[fallthrough]]` is taken OUT of the output and compiled six ways.  It
#               is NOT a directive -- the output still has exactly eleven, all
#               `#include` -- and C23 is not a new dependency: MEASURED and computed,
#               `-std=c11` on the whole file gives the SAME number of errors before this
#               phase and after it.
#   WARNINGS    `-Wformat=2` gives THE IDENTICAL 115 `-Wformat-nonliteral` warnings in
#               THE IDENTICAL 53 functions, before and after -- phase 22's invariant,
#               and what proves the six survivors were not disturbed.  Two controls
#               break it in opposite directions.
#   SYMBOLS     `nm -u` is THE SAME SET, as a `comm` empty in BOTH directions, and
#               `main` is still the only external symbol.
#   THE BINARY  `cmp`, with a control that moves it: one `[[fallthrough]];` replaced by
#               `break;` must give a different binary, which is what keeps the equality
#               from being two numbers agreeing (CLAUDE.md).
#
# ONE MEASUREMENT ABOUT THE TOOL RATHER THAN THE FILE, and it is CLAUDE.md's
# `-fsyntax-only` lesson arriving on a second warning.  `-fsyntax-only` does report
# `-Wunused-parameter`, `-Wformat-nonliteral` and every syntax error, so the sections
# that want those use it and are seconds instead of minutes.  It does NOT report
# `-Wimplicit-fallthrough`, which needs the CFG: measured, the control below warns 18
# times under `-c` and ZERO times under `-fsyntax-only`.  A fallthrough section written
# with `-fsyntax-only` would have passed while checking nothing.

# THE BODY IS GO: tools/go/internal/check/zero24.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/canon.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zerodelta.sh
set -eu

work=${1:?usage: zero24-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero24-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero24 "$work" "$state"
