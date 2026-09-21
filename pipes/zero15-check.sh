#!/bin/sh
# Zero phase 15, the check -- the character classes, the numbers and the sort.
# See pipes/zero15-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero15-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero15-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from.
#
# THE DECLARED DELTA IS NOTHING AT ALL, AND IT IS A THIRD KIND OF EMPTY DECLARATION.
# Phase 9's was code that could not run; phase 13's was a possibility that had never
# existed; this one is an EQUALITY.  The code this phase replaces runs constantly --
# `towupper` alone is entered 892 times in a trivial session, before 'casemap' has
# even been applied -- and what is claimed is that the replacement computes the same
# answer.  So there is no must-differ probe, every behavioural probe is a
# MUST-NOT-DIFFER, and the weight of the evidence sits on equivalence instead:
#
#   muslcase --verify   re-derives all 1,114,112 codepoints from THIS
#                                MACHINE'S libc through ctypes and compares them
#                                with the 187 + 171 rows the phase shipped.  The
#                                table is checked against the only authority there
#                                is, not remembered.
#   muslctype --verify  slices the seventeen functions OUT OF THE SOURCE
#                                THIS PHASE PRODUCED, compiles them with -Wall
#                                -Wextra and runs them beside libc's.
#
# Both are proven able to fail: perturbing one `convertStruct` offset, one `& 0x5f`,
# one comparator direction and one `return` in the binary search each makes the
# matching tool refuse.
#
# THE HEADER CONTRACT IS ASSERTED HERE AND NOT LEFT TO PHASE 16.  A copy of the
# produced source with `#include <ctype.h>` and `#include <wctype.h>` deleted must
# compile SILENTLY, and the same deletion on the source this phase was HANDED must
# fail.  That is a check that can fail in both directions, and it is what phase 16
# needs to be true before it can move.  Neither copy is left in the tree: this phase
# changes no directive, and the count stays 18.
#
# FIVE THINGS ARE PROVED.
#
# 1. THE SOURCE, as counts.  Nothing <ctype.h> or <wctype.h> provides is CALLED
#    anywhere, `iswupper` is gone, and the seventeen musl_ functions are defined
#    once each.  The count is call-shaped and not `\b`-shaped: "isprint" is also an
#    option name in a string literal, and a word count says 1 on a file that calls
#    it nowhere.
#
#    THE TRAPS, ALL MEASURED:
#      * `nm -u` UNDER-REPORTS <ctype.h> BY FIVE NAMES.  isalpha, isdigit, isgraph,
#        islower and isupper are function-like macros in musl, so a source that
#        calls them has no undefined symbol to show for it.  A check written from
#        the symbol list alone passes on a phase that left all seventeen sites.
#      * `latin1flags`, `latin1upper` and `latin1lower` MUST SURVIVE.  They are read
#        only from the unreachable arms this phase deliberately does not touch, and
#        a check that expected them to go would fail on a correct phase.
#      * `utf_convert` GAINS two callers and keeps its own.
#      * THE BINARY GROWS.  805,544 against 803,912 on this phase's input: the 358
#        rows are data the image did not carry before, and the musl objects they
#        replace were smaller, because musl packs the same mapping into 16,998 bytes
#        of two-level base-6 table.  A phase check that assumed removal means
#        shrinkage would fail here.
#
# 2. THE LIBC SURFACE, NAMED AS A SET AND NOT AS A COUNT -- `atoi atol bsearch
#    isalnum iscntrl ispunct qsort tolower toupper towlower towupper` and nothing
#    else -- with the terminal, the memory and the message layer asserted still
#    there, and ZERO-PLAN.md 4b's invariant asserted again.
#
# 3. THE TWO EQUIVALENCE TOOLS, above.
#
# 4. FOURTEEN PROBE SESSIONS ON BOTH BINARIES, byte-identical, each required to be
#    doing something.  The corpus is ASCII-only and seeds itself by typing, so it
#    cannot reach Unicode case folding, `'casemap'`, the four bsearch tables or the
#    sort at all -- which is exactly why `tools/zerodelta.sh` saying "nothing moved"
#    is not enough on its own.
#
# 5. AND THE SORT, WHICH NO RECORD CAN SEE.  `:undolist` is wiped by the Press-ENTER
#    redraw before the `\x1b[?25h` that ends a step, so its row order is read out of
#    the raw stdout stream.  It is compared rather than sha'd because the rows carry
#    "0 seconds ago", which is the one nondeterminism the corpus scrubs.

# THE BODY IS GO: tools/go/internal/check/zero15.go and tools/go/internal/check/zero15probes.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/enumvals.sh
#   tools/musl-case.txt
#   tools/musl-ctype.txt
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero15-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero15-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero15 "$work" "$state"
