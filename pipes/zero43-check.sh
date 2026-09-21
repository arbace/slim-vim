#!/bin/sh
# Zero phase 43 -- the proof.  See pipes/zero43-edit.sh for what the phase does.
#
# Usage: pipes/zero43-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# WHAT THIS PHASE HAS TO SHOW, AND WHY IT IS NOT THE USUAL LIST.  Every keystroke in
# this editor reaches its text through `ml_find_line()`, and this phase changes how that
# function finds every block.  So the recording is not the weak part of the evidence
# here -- it is the strong part, PROVIDED the recording can see the text layer at all,
# which it could not before zero phase 40.  Nine sections:
#
#   1  the source, with what the EDIT took and what the SWEEP took kept apart, and every
#      name that leaves partitioned against a reason
#   2  THE BLOCK ARITHMETIC, DERIVED: `sizeof(PTR_EN)` and `pb_count_max` computed by
#      compiling the structs out of both sources, because a pointer entry that has lost
#      a field holds MORE children per page and that is what decides whether phase 40's
#      corpus still reaches the code this phase changes
#   3  the build: no warning, one external symbol, tools/phasecheck.sh, tools/canon.sh
#      a no-op, `nvidx`, `orphanopts`, `zhostonly`
#   4  the cut `make editor.c` makes: the core is still plain C above the first
#      `#include` and its interface to the host is the same thirteen names
#   5  THE SIXTEEN MEMLINE CASES, MEASURED AND NOT ASSERTED: how many data blocks each
#      one makes, how deep it descends, and whether it splits the root -- on the input
#      and on the output, which must agree case for case
#   6  two whole recordings, byte for byte
#   7  the phase's own deep sessions, at a size DERIVED from section 2 so that the root
#      really splits, with an instrument that says it did
#   8  three controls, each of which must move something, and two of which move nothing
#      a screen case can see
#   9  E323, the one string this phase changes: an instrument that says no record in a
#      whole recording reaches the arm, and a forced build that exhibits both messages
#
# THE ARENA RIG, AND WHY THIS CHECK RAISES IT.  Zero phase 41 made `host_free` a no-op
# and gave `host_alloc` a fixed arena.  ``zmemline`` builds its buffers by
# replaying a macro with a COUNT -- there is no file argument (phase 5), no `:edit`
# (phase 8) and no `:read` (phase 7), so a counted replay is the only way in -- and
# stuffing `N@q` into the typeahead grows a buffer N times without freeing any of the
# copies, which is quadratic in N.  So the largest cases may not fit an arena sized for
# the corpus phase 41 could see.  That is phase 41's number and not this phase's claim,
# and this check must not depend on it either way: sections 5 and 7 build their own pair
# with the arena raised, state the figure, and require the two binaries to agree there.
# Section 6 records the binaries AS BUILT, which is the pipeline's own question.

# THE BODY IS GO: tools/go/internal/check/zero43.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/canon.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zerodelta.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero43-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero43-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero43 "$work" "$state"
