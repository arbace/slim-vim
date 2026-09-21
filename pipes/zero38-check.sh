#!/bin/sh
# Zero phase 38, the check -- the eight terminal names go, leaving two.
# See pipes/zero38-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero38-check.sh <work-dir> <state-dir>   (run from the repository root)
#
# Runs after pipes/zero38-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old.c`, the source this phase was HANDED,
# and `old`, that source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# NOTHING BELOW IS A NUMBER THAT WAS OBSERVED.  Which names go is the input's table
# minus the output's; which capability tables die follows from that; what a refused
# name leaves the terminal as is MEASURED from the new binary, by asking it with no
# `+set term=` at all; and the nineteen rows are however many
# `termcheck` names.  So the rules stay true of a file this check has never
# seen, which is what makes them rules.
#
# WHAT IS CLAIMED, in nine parts:
#
#   THE CUT      the output's table is the input's MINUS a set, every surviving row
#                byte for byte the row it was, and every capability table the removed
#                rows pointed at -- and nothing else -- gone from the file.  Which
#                tables those are is COMPUTED from the input, on text whose string
#                literals are blanked, because `builtin_xterm` is also a literal.
#   THE PARTITION  every string literal in the INPUT whose content is a removed name
#                falls in one of four classes, and in the OUTPUT only the last class
#                is left: the counted prefix tests in vim_is_xterm(), where the name
#                is five characters and not a terminal.  A leftover refuses.  This is
#                recomputed here and does not read the edit's answer.
#   THE FALLBACK  every terminal name written as a literal OUTSIDE the table names a
#                row that still exists, and the message that announces the fallback
#                names the same one.  THE CONTROL is this phase's own output with the
#                repair left out, which must move the two `-T` rows and print E437 --
#                an editor with no cursor motion.  A repair with no control is a
#                claim; this one is measured.
#   THE CLAUSE   the xterm-family special case is dead and not merely unused.  TWO
#                measurements: the output with the clause RESTORED records byte for
#                byte what the output records, so removing it changed nothing; and
#                the same two sources with a marker inside the clause enter it in
#                EVERY screen record on the input and in NONE on the output.
#   THE TABLE    the nineteen rows before and after, side by side, in this check's
#                output.  Exactly the names that lost a row moved, each from
#                resolving to a refusal at the MEASURED default, and every other row
#                is byte-identical.  TWO CONTROLS, in opposite directions: a row
#                deleted from the output's own table moves exactly one of the
#                nineteen from resolving to refused, and a removed name put back
#                moves exactly one from refused to resolving.  An instrument that
#                cannot fail is not evidence.
#   THE FAMILY   the `xterm` row was not one name: find_builtin_term()'s special case
#                handed its table to every name vim_is_xterm() accepts, and NOT ONE of
#                those is among the nineteen.  So the phase owes probes, and the names
#                are read out of vim_is_xterm()'s own prefix list in the source this
#                phase was handed: each must resolve on the old binary and be refused
#                on the new.
#   SYMBOLS      `nm -u` is THE SAME SET, as a `comm` empty in both directions, and
#                that is a statement rather than a disappointment: this phase deletes
#                DATA -- three static arrays and eight rows -- and data calls nothing.
#                `nm --extern-only --defined-only` is still exactly `main`.
#   THE CUT (2)  `awk '/^ *# *include / { exit }'`, zero.mk's own rule, on the INPUT
#                and on the OUTPUT: eleven directives, none above them, 0 errors
#                under -fsyntax-only either side, and the boundary's warning set --
#                which IS the core -> host interface -- UNCHANGED.  The input's set
#                is computed here and never written down.
#   STRUCTURE    `zhostonly`, phase 20's structural check, and
#                tools/phasecheck.sh.

# THE BODY IS GO: tools/go/internal/check/zero38.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero38-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero38-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero38 "$work" "$state"
