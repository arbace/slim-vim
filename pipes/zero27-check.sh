#!/bin/sh
# Zero phase 27, the check -- THE MOVE, and the boundary as an assertion.
# See pipes/zero27-edit.sh, ZERO-PLAN.md 4c and .claude/briefs/zero-reorg.md 5.
#
# Usage: pipes/zero27-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero27-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# WHAT IS CLAIMED, in eight parts:
#
#   THE MOVE      A MOVE AND NOTHING ELSE, stated as a multiset: every line of the
#                 output is a line of the input except the THIRTY-TWO this phase
#                 writes -- 20 enumerator lines and 12 static_asserts -- and NOT ONE
#                 line of the input is missing.  A phase that moved code and also
#                 changed a character of it could not say that.
#   THE CUT       the four parts the brief asks for, and the two equalities that make
#                 the cut a product: it is a PREFIX (`head -n N` is `cmp`-exact) and
#                 the cut plus the remainder IS the file, byte for byte.
#   THE BOUNDARY  the cut's warning set, computed two ways and required equal: gcc's
#                 `'X' used but never defined`, and the names DECLARED above the cut
#                 and DEFINED below it, read out of the text.  Thirteen, and they are
#                 named here so that widening the interface is loud.
#   FOUR BREAKS   the three the brief measured as SILENT in the ordinary build and
#                 caught only here -- a `#define` above the cut, an `#include` back at
#                 the top, and one core function moved below the cut -- each built
#                 both ways; and a fourth that is NOT silent and is the whole reason
#                 phase 26 came first: `#include <limits.h>` at line 1, where the
#                 twelve enumerators become their own values and the compiler says
#                 `expected identifier before numeric constant`.
#   THE CONSTANTS the twelve are in the PRODUCT and they are compiled: one derivation
#                 deliberately wrong is `static assertion failed`.  And the reason the
#                 assert restates the derivation rather than naming the enumerator is
#                 MEASURED, not argued: the same wrong enumerator with the assert
#                 written `INT_MAX == INT_MAX` builds in SILENCE.
#   THE TRAP      the `static` prototype trap in its NEW shape.  Phase 26 measured it
#                 as `error: static declaration of 'malloc' follows non-static
#                 declaration`, which needed <stdlib.h> above it.  Here there is no
#                 second declaration, so it is `'malloc' declared 'static' but never
#                 defined [-Wunused-function]` on <stdlib.h>'s own line, which is the
#                 one part of phase 26's evidence this phase had to replace -- and it
#                 is WEAKER than the brief predicted: MEASURED, it links anyway and the
#                 binary is byte-identical, so it is a warning the sweep catches.
#   SYMBOLS       `nm -u` is THE SAME SET, as a `comm` empty in BOTH directions, and
#                 `main` is still the only external symbol.  Moving definitions inside
#                 ONE translation unit frees nothing and needs nothing: THE CLAIM OF
#                 THIS PHASE IS STRUCTURAL AND NOT A SYMBOL COUNT.
#   BEHAVIOUR     the declared delta is NOTHING AT ALL.  Two full recordings, of the
#                 binary this phase was handed and of its own, are BYTE-IDENTICAL.
#                 tools/zerodelta.sh is run by tools/phaserun.sh after this check and
#                 is the second opinion.
#
# THERE IS NO `cmp` HERE AND THERE CANNOT BE.  Phases 16, 23 and 24 could each say
# "the binary is the same bytes"; this one moves 1,800 lines of definitions, so every
# address below the first of them moves and the image is a different one of the same
# size.  What replaces it is the multiset equality above -- the source is the same
# lines -- plus the recording.
#
# AND `zhostonly`, WHOSE EXCEPTIONS THIS PHASE CHANGED.  The core now writes
# `enum { SIGHUP = 1 };` for itself and `static_assert(1 == SIGHUP, "SIGHUP");` below
# the includes to check it, so `<file scope>` says SIGHUP and SIGTERM twice each where
# it said neither.  Both are outside the host region -- the region begins at
# host_winch_pending and the includes are above it -- so the tool refuses until the
# phase comes and writes the new counts beside the old, which is what it is for.

# THE BODY IS GO: tools/go/internal/check/zero27.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/canon.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero27-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero27-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero27 "$work" "$state"
