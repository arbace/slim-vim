#!/bin/sh
# Zero phase 32, the check -- the clock crosses the boundary.
# See pipes/zero32-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero32-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero32-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# WHAT IS CLAIMED, in eight parts:
#
#   ARITHMETIC  computed FROM THE INPUT: the core does not name `time` at all, the four
#               mentions it had having become none; `host_time` is 8 above the boundary
#               and 1 below; the libc prototype block loses exactly one line and keeps
#               every other entry; the core loses 7 lines and the host gains 7.
#   THE GUARANTEE
#               THE PART OF THIS PHASE THAT COULD SILENTLY REGRESS, as FOUR compiles.
#               `long time(long *tp);` was what pinned `time_T`'s width, and it is
#               replaced by a static_assert rather than deleted.  m1 shows the prototype
#               really was a check (on the INPUT, written wrong: `conflicting types for
#               'time'`); m2 shows what it did NOT check (on the INPUT, `time_T`
#               perturbed to `int` with the prototype untouched: SILENT); p1 shows the
#               hole this phase would leave without its replacement (the OUTPUT with the
#               assert deleted and `time_T` perturbed: SILENT); and p2/p3 show the
#               replacement closing it (`static assertion failed: "time_T is time_t"`).
#               The assert is therefore STRICTLY STRONGER than the prototype, and the
#               check says so with m2 rather than claiming an equivalence.
#   THE BOUNDARY
#               `make editor.c`'s cut, computed here by the same awk clause on BOTH
#               sides: 0 directives, `-fsyntax-only` with no error and no warning that
#               is not a boundary name, and the warning set compared AT RUN TIME with
#               the input's -- exactly `host_time` arriving, nothing gone, 13 -> 14.
#               The thirteen are never written out: phase 28 renamed one of them and a
#               list here would already be stale.
#   CANON       tools/canon.sh is a NO-OP on the output.
#   HOST        `zhostonly`, unchanged: `time` is not in its vocabulary and this
#               phase deliberately does not add it -- see THE TOOL THIS PHASE DOES NOT
#               EDIT below.
#   SYMBOLS     `nm -u` is THE SAME SET -- 17 names, `comm` empty in both directions --
#               and `main` is still the only external symbol.  **`time` DOES NOT LEAVE**,
#               and this is said as an equality rather than left for a reader to expect
#               otherwise: the host still calls it to implement host_time(), and a symbol
#               leaves when its last caller leaves the FILE, which is the split and not
#               this phase.  That is phase 28's sentence about `gettimeofday`, and the
#               two clocks are now in exactly the same position.
#   THE READS   THE INSTRUMENTED PAIR, and it is the evidence the recording cannot give.
#               `write(2, "TICK\n", 5)` at EVERY clock read on both sides -- on the input
#               inside vim_time() and, as a comma expression, at each of
#               ui_focus_change's two direct reads; on the output inside host_time(),
#               which is now every read there is.  The two instrumented 102-case
#               recordings must be BYTE-IDENTICAL, which is a statement about the screens
#               AND about the number and the order of the clock reads in every case.
#               Plus focus probes, because no corpus case reaches ui_focus_change at all.
#   BEHAVIOUR   the declared delta is NOTHING AT ALL: two full recordings, of the binary
#               this phase was handed and of its own, byte-identical across all 106
#               records.  tools/zerodelta.sh is run by tools/phaserun.sh after this check
#               and is the second opinion.
#
# THE CORPUS CANNOT REACH ui_focus_change AND THE PHASE SAYS SO RATHER THAN HOPING.
# `ui_focus_change()` is called from `handle_key_without_mapping`'s KE_FOCUSGAINED and
# KE_FOCUSLOST arms, and those key codes arrive as `\033[I` and `\033[O`, which
# `set_termname()` registers unconditionally.  So a keystroke file CAN drive it -- which
# ZERO-PLAN.md 2l calls a hazard (a typed Escape followed by `[` is read as a key code)
# and which is exactly what is wanted here.  The probes are:
#
#   focus        \033[O \033[I         3 TICKs on both binaries
#   focus_twice  \033[O \033[I x2      4 TICKs on both binaries
#
# and the arithmetic is worth writing down because the control turns on it.  `focus_state`
# starts MAYBE, so the first `\033[O` calls ui_focus_change(FALSE) -- which reads NOTHING,
# `in_focus &&` short-circuiting -- and the first `\033[I` calls it with TRUE, where
# `last_time` is 0, the test is true and BOTH reads happen.  On the second round the test
# is FALSE, so only the condition reads.  0 + 2 + 0 + 1, and one more for the `:q!` that
# reaches add_to_history: four.
#
# AND THE CONTROL IS THE QUESTION THE USER ASKED, MADE INTO A PROGRAM.  `hoist` is the
# output with ui_focus_change's two reads collapsed into one local -- which is what
# "could the two reads now straddle a second boundary differently" would mean if it were
# true -- and it reads the clock ONCE PER CALL, unconditionally: 1 + 1 + 1 + 1 + 1 = 5
# where the product gives 4.  So the instrument can see a collapsed read, the product
# does not collapse one, and the answer to the question is measured rather than argued:
# two reads before, two reads after, in the same two statements and the same order.
#
# A HAZARD THIS PHASE FOUND IN THE SHARED RECORDING, NOT WORKED AROUND HERE.  Comparing
# two FULL recordings is load-sensitive in exactly three records, and this phase is the
# one that would notice.  `tools/zrec.py` scrubs the undo message's elapsed time to
# `<ago>` PADDED TO THE WIDTH IT REPLACES, so the SCREEN is protected -- but the record
# also carries `--- stream <len> sha=<...>`, and that digest is taken over the RAW byte
# stream, where "0 seconds ago" and "1 second ago" are 13 bytes and 12.  MEASURED with a
# control built for it, `add_time()` reporting one second more: exactly three records
# move -- undo_after_ins, undo_block, undo_redo, which are exactly the three whose screen
# carries `<ago>` -- and in each of them exactly ONE line moves, the `--- stream` line,
# with the 24 screen lines byte-identical.  Under a 33-way concurrent `make zero-verify`
# the gap between `u_savecommon()`'s stamp and `undo_time()`'s read can straddle a second
# tick, and one such run failed here on `undo_after_ins` alone.
#
# IT IS NOT THIS PHASE'S TO FIX AND NOT THIS PHASE'S TO PAPER OVER.  Every zero phase
# since 3 compares two full recordings and every one of them is exposed; so is
# tools/zerodelta.sh, which compares against baselines recorded the same way.  Hashing
# the SCRUBBED stream in tools/zrec.py would close it, and would re-key all 33 zero
# phases and require .reference/zero-baselines to be recorded again.  A private exclusion
# HERE would be a check narrowed to fit what it saw, would leave zerodelta failing on the
# same load, and is refused: the comparison below stays an exact `diff -rq`.  The reading
# that matters for THIS phase is that the exposure is unchanged by it -- the undo path
# reads the clock the same number of times before and after, which is what the
# instrumented pair measures.
#
# THE TOOL THIS PHASE DOES NOT EDIT, and it is a decision rather than an oversight.
# ``zhostonly`` asserts that the core names none of the host's vocabulary, and
# `gettimeofday` joined that vocabulary at phase 28 for exactly this shape of reason.
# `time` is NOT added here.  Adding it would re-key phases 20, 21, 25, 26 and 27, whose
# checks run the tool on their own output, and every one of those boundaries has the core
# calling `time()` -- so each would need a named exception with a count, and four
# boundaries would have to be re-verified to buy a fact this check already asserts
# directly and more strongly: `\btime\b` is at ZERO above the boundary, computed on the
# literal-stripped text, and the `make editor.c` cut compiles with `host_time` as a
# boundary name.  The tool is still RUN, on this phase's output, so that nothing else in
# its vocabulary moved.

# THE BODY IS GO: tools/go/internal/check/zero32.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/canon.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero32-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero32-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero32 "$work" "$state"
