#!/bin/sh
# Zero phase 39, the check -- `-T {term}` goes, and the command line is `+{command}`.
# See pipes/zero39-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero39-check.sh <work-dir> <state-dir>   (run from the repository root)
#
# Runs after pipes/zero39-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# `old`, that source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags, and
# `enums-before`, that binary's DWARF enumerator values.
#
# NOTHING BELOW IS A NUMBER THAT WAS OBSERVED.  Which option letters went is the
# input's `switch (c)` minus the output's; which command lines must therefore move is
# computed from those letters over `zargv`'s own list; what a refused terminal
# name leaves the terminal as is measured from the new binary; and the boundary's
# interface is computed from the input.  So the rules stay true of a file this check
# has never seen, which is what makes them rules.
#
# WHAT IS CLAIMED, in nine parts:
#
#   THE CUT      the option letters are gone, `want_argument`, `mainerr_arg_missing`,
#                ME_GARBAGE, ME_ARG_MISSING and `requested` are at 0 mentions, the
#                parser is ONE `if (argv[0][0] == '+')` and one else, `mparm_T` has no
#                `term` member and every `.term` left belongs to another struct.
#   THE ROWS     main_errors[] is indexed by the ME_* enumerators, so the check is
#                DWARF and not the build: exactly the two enumerators removed are
#                gone, exactly ME_EXTRA_CMD moved, and by exactly one.
#   THE COMMAND LINE  `zargv`'s thirty invocations, before and after, side by
#                side.  A row must move IF AND ONLY IF one of its words is an option
#                spelling the removed letters -- computed from the two switches, not
#                written here -- and each row that moves must have done something
#                ELSE on the binary this phase was handed, or it proves nothing.
#   THE FALLBACK the three statements after the refusal cannot run.  TWO measurements:
#                the output with the whole arm RESTORED, report_default_term() and all,
#                records byte for byte what the output records; and the same marker in
#                the same place, reached through host_message(), is in exactly the `-T`
#                records on the INPUT and in NONE on that control.
#   THE ARM      and the half that stays is entered: the same instrumented pair,
#                asked `+set term={unknown}` on a real pty, takes the no-screen test's
#                arm on both, which is what makes the fold ALWAYS and not a guess.
#   THE MESSAGE  report_term_error() still runs -- it is the run-time refusal's, not
#                the fallback's, which is the payoff phase 38 predicted and did NOT
#                get -- and it no longer promises a default that cannot happen.  Both
#                halves on a pty, with E522 and the terminal unchanged either side.
#   256-COLOUR   the test does NOT fold, and that is measured in both directions: with
#                the name test forced TRUE exactly one row of the terminal table moves,
#                with it forced FALSE eighteen do.  And folding `requested` into `term`
#                is neutral where the two differ -- the `builtin_` spellings of both
#                surviving names answer identically on both binaries.
#   SYMBOLS      `nm -u` is THE SAME SET, as a `comm` empty in both directions: this
#                phase deletes a parser arm and calls nothing new.  `nm --extern-only
#                --defined-only` is still exactly `main`.
#   THE CUT (2)  zero.mk's own rule on the INPUT and the OUTPUT: eleven directives,
#                none above them, 0 errors under -fsyntax-only either side, and the
#                boundary's warning set -- computed here and never written down --
#                UNCHANGED.  Then `zhostonly` and tools/phasecheck.sh.

# THE BODY IS GO: tools/go/internal/check/zero39.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/enumvals.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero39-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero39-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero39 "$work" "$state"
