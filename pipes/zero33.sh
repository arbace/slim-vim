#!/bin/sh
# Zero phase 33 -- the terminal table is asked with `+set term={name}`.
#                  See ZERO-GOAL.md, ZERO-PLAN.md 4c.
#
# Usage: pipes/zero33.sh <work-dir>      (run from the repository root)
#
# NO SOURCE CHANGE AT ALL: r33's zero-vim.c is its input's, byte for byte, and this
# phase asserts it first and last.  What changes is one fifth of how every later
# phase is measured.  This is zero phase 3's shape exactly -- the other phase that
# changes no source and replaces an instrument -- and it is here for the same reason:
# a harness that cannot see a phase must be fixed BEFORE the phase, never after.
#
# WHAT WAS WRONG WITH THE OLD QUESTION.  ``ztermcheck`` put the name it was
# asking about in `$TERM`, which is `termcheck`'s question and whim's.  But
# whim phase 19 removed the `getenv("TERM")` from `termcapinit()` -- "the terminal is
# what the build says" -- and left a compiled `"xterm-256color"` in its place.  So
# every row of `.reference/zero-baselines/ref-term.txt` read
#
#     TERM='vt100'              -> term=xterm-256color t_Co=256
#
# and the table was as many ways of recording that the environment does nothing.
# MEASURED, and this is the finding that makes the phase rather than the argument:
# a prototype that DELETED eight of the ten built-in terminal names and three of the
# nine capability tables -- 118 lines of terminal description -- passed
# `tools/zcompare.py` against the real baselines DECLARING NOTHING AT ALL.  A phase
# is allowed to declare nothing only when the instrument could have seen it; here it
# could not.
#
# WHAT THE NEW QUESTION IS.  `+set term={name}`, which reaches `did_set_term()`
# rather than `termcapinit()`'s compiled default, and which is `+{command}` -- the
# one facility ZERO-PLAN.md decision 8 promises to survive every phase.  It is NOT
# `-T {term}`: measured, a `-T` harness records nothing but `(none)` against a binary
# with no `-T`, which is precisely the failure the tool's own docstring exists to
# prevent, and `-T` is being abandoned.  `termcheck` is imported and
# untouched -- it is named by tools/whimdelta.sh and tools/verify.sh and its bytes
# are in every whim stage's key (ZERO-GOAL.md rule 9).
#
# WHY RE-RECORDING THE BASELINES IS LEGITIMATE, which is the delicate part.
# CLAUDE.md's rule is "never regenerate it from the current binary, which would make
# the comparison self-fulfilling".  The mistake it names is a pipeline re-recording
# from its OWN OUTPUT.  Zero phase 0 does the opposite and pipes/zero0.sh enforces
# it: the baselines come from `whim-vim.c`, the pipeline's immutable input, built
# with WHIM's compile line, recorded three times and required identical.  Nothing
# zero produces is on the recording side.  The same input, the same compile line,
# the same five harnesses; one of the five now asks its question a different way.
# Section 4 below is the independent check that the answer is the same one
# everywhere, which is the property a baseline must have and a self-fulfilling one
# cannot be tested for.  `pipes/zero0.sh` REFUSES a differing baseline set rather
# than overwriting it, so the incantation is
#
#     rm -rf .reference/zero-baselines .cache/r0 && make zero-phase-0
#
# and `rm -rf .cache/r0` alone is not enough.  Measured: without the first path it
# exits 1 naming ref-term.txt; with it, 31 s.
#
# NOTHING HERE IS A NUMBER THAT WAS OBSERVED.  The table has as many rows as
# `termcheck` has names; which of them resolve is read out of
# `builtin_terminals[]` in the source the phase was handed; and what a REFUSED name
# leaves the terminal as is measured from the binary, by asking it with no
# `+set term=` at all.  So the rules below stay true of the phase that deletes eight
# of those names, and of anything else that changes the table -- they say what the
# table MEANS, and the recording itself is what says what it currently is.
#
# WHAT THIS PHASE PROVES, in order, each depending on the one before:
#
#   1. the tree is untouched: zero-vim.c is what the phase was handed;
#   2. it builds with the boundary's flags, is still absolutely static, and `main` is
#      still the only external symbol.  Every SOURCE fact is the input's by the sha
#      in 1; these are facts about a binary that was rebuilt;
#   3. THE NEW TABLE MEANS WHAT IT CLAIMS: one row per name asked, every name in
#      `builtin_terminals[]` resolving TO ITSELF, and every other name refused with
#      an `E5NN` AND the terminal left at the compiled default;
#   4. IT IS THE SAME TABLE EVERYWHERE.  `whim-vim.c`, built with whim's own line,
#      records exactly those rows -- and so does every recorded boundary binary, one
#      digest across all of them.  THAT is what makes the re-record safe: the
#      baseline and every phase's recording move together, so no earlier phase's
#      declared delta changes;
#   5. THE INSTRUMENT IS DETERMINISTIC: three whole recordings of that binary, byte
#      for byte identical, stream digests included;
#   6. THE INSTRUMENT CAN FAIL, AND THE ONE IT REPLACES CANNOT.  A scratch copy of
#      the source with ONE row deleted from `builtin_terminals[]` must move EXACTLY
#      that name's row, from resolving to refused -- and must move NOTHING AT ALL
#      when the same names are asked the old way.  A corpus that cannot fail is not
#      evidence, and that pair is the whole of this phase in one measurement;
#   7. the declared delta holds -- NOTHING, and nothing new: tools/zerodelta.sh
#      --phase 33 against the re-recorded .reference/zero-baselines.

# THE BODY IS GO: tools/go/internal/check/zero33.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/st.sh
#   tools/zerodelta.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero33.sh <work-dir>}
exec tools/st.sh check zero33 "$work"
