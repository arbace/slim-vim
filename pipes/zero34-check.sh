#!/bin/sh
# Zero phase 34, the check -- the core stops reallocating.
# See pipes/zero34-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero34-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero34-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# WHAT IS CLAIMED, in seven parts:
#
#   ARITHMETIC  computed FROM THE INPUT: `realloc` 3 -> 0 above the boundary and 1 -> 1
#               below it, the libc prototype block one line shorter than the input's
#               (counted, never stated -- phases 31 and 35 also shrink it), the file
#               +10 lines, the directives unmoved relative to the text, and
#               tools/canon.sh a NO-OP.
#   THE HARNESS THE PHASE'S REAL EVIDENCE, because every way this rewrite can be wrong
#               is a memory bug and no screen recording can see one.  ga_grow_inner(),
#               musl_memcpy(), musl_memset(), garray_T and get_keystroke's extension
#               block are EXTRACTED AT RUN TIME from the input source and from the
#               output, wrapped in the same driver, built with AddressSanitizer and
#               driven from empty through eight doublings, through a failed
#               allocation, and through the 100-byte extension.  The two transcripts
#               must be IDENTICAL and neither may report a finding.
#   CONTROLS    seven, each a way the rewrite could be wrong, SIX OF WHICH MOVE and one
#               of which does not -- which is reported rather than hidden (zero phases
#               22 and 31 set that precedent).  Each mover is required to give its own
#               named sanitizer finding, so "the harness noticed" is not one bucket.
#   THE GUARD   what `if (gap->ga_data != nullptr)` actually buys, measured in both
#               directions.  It changes NO behaviour here -- a null `ga_data` implies
#               `ga_maxlen == 0` implies `old_len == 0`, and musl_memcpy's `for (; n;
#               n--)` never dereferences -- and the check says so.  What it buys is on
#               the page: a driver whose musl_memcpy announces a null source reports 0
#               from the output and 8 from the unguarded control.
#   SYMBOLS     `nm -u` is THE SAME SET, as a `comm` empty in BOTH directions, and
#               `realloc` is STILL IN IT.  A reader expects a phase that removes a call
#               to move the count; this one does not, because adjust_types() is below
#               the boundary and still calls it.  Phases 14, 15 and 21 each require
#               `realloc` to be undefined and all three still pass.
#   THE CUT     `make editor.c`'s rule run on both sides: 0 directives, 0 errors under
#               `-fsyntax-only`, and the whole warning set -- the core -> host boundary
#               -- IDENTICAL to the input's, compared name by name at run time.
#   BEHAVIOUR   the declared delta is NOTHING AT ALL, and here that is STRONG evidence
#               and not weak.  ga_grow_inner is on the path of every growarray: an
#               instrumented build of the INPUT marks 2,739 first grows and 1,550
#               later ones in 104 of the 106 records, and the IDENTICAL instrument on
#               the OUTPUT marks the same 2,739 and 1,550.  Two full recordings are
#               byte-identical, and a build whose copy length is 0 moves 102 of the 102
#               screen cases.
#
# THE SHRINK QUESTION IS ANSWERED AND NOT ASSUMED.  `musl_memcpy` copies the OLD size at
# both sites, which is wrong if either site can ever ask for less than it has.  Neither
# can: the same instrument marks a shrink at 0 of 106 records, ga_grow_inner's only
# caller enters it only when `ga_maxlen - ga_len < n`, and get_keystroke adds 100
# immediately above the call.  The input's own `musl_memset(pp + old_len, 0, new_len -
# old_len)` already relied on it -- the length is unsigned -- so the property is the
# input's and not this phase's to establish.
#
# WHY THE UNIT HARNESS AND NOT A PROBE ON THE EDITOR.  get_keystroke's extension is
# UNREACHABLE in a recording, and that was measured rather than guessed: an instrumented
# build of the input marks each of the five `continue` paths in its loop at 0 of 106
# records, so `len` never exceeds one ui_inchar() and `maxlen` never falls below 10.  A
# pty session feeding a partial escape sequence sixty times does not reach it either.
# Extracting the block is the only instrument that can drive it, and it drives the
# input's version and the output's through the same driver.

# THE BODY IS GO: tools/go/internal/check/zero34.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/canon.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero34-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero34-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero34 "$work" "$state"
