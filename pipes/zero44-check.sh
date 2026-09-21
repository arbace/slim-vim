#!/bin/sh
# Zero phase 44's check -- de-page the leaf.
#
# Usage: pipes/zero44-check.sh <work-dir> <state-dir>   (run from the repository root)
#
# THE DECLARED DELTA IS NOTHING AT ALL AND IT IS THE WEAKEST KIND THERE IS.  The code
# changes, the binary moves, and the claim is that a replacement does what the thing
# it replaces did -- which is zero phases 14 and 15's kind and no other.  There is no
# `cmp` to be had: every line of the buffer is stored somewhere else now.  So the
# recordings are the floor and not the evidence, and what carries the phase is the
# controls: eleven builds of this phase's own output with one thing changed, eight of
# which MUST move a recording and three of which must not, each of the three with the
# reason it cannot be seen written beside it.
#
# WHAT IS CHECKED, in the order it is cheapest to fail:
#
#   1  the product builds from a tree the clean really emptied
#   2  THE PARTITION.  Every mention of db_free, db_txt_start, db_txt_end, db_index,
#      the stolen top bit, ML_APPEND_MARK and offsetof(DATA_BL) is gone -- and the
#      input's count of each is read off the input, never written here
#   3  the representation, read out of the output: the record's three members, the
#      block's three, and the static_assert that keeps a leaf inside its page
#   4  THE LIFETIME RULE as a partition over every assignment to a record's text
#   5  two full recordings, byte for byte the input's, and identical to each other
#   6  the memline corpus REACHES the tree, measured with an instrumented pair
#   7  WHAT THE REPRESENTATION COSTS THE ARENA, which is the one resource claim a
#      per-line allocation owes and which no recording can make
#   8  the controls
#   9  nm -u unchanged both ways, the cut, and the ordinary phase checks
#
# WHY SECTION 6 EXISTS AND WHY IT IS THIS PHASE'S AND NOT PHASE 40'S.  Before phase
# 40 a zero-vim with one line deleted from ml_find_line()'s descent recorded all 102
# screen cases byte for byte.  This phase rewrites the leaf that corpus was built to
# see, so it owes the measurement in both directions: the output must still reach the
# splits, and the input's own numbers are taken in the same run with the same
# instrument, so that "it reaches them" is a comparison and not an assertion.
#
# ONE PATH IS REMOVED ON PURPOSE AND THE SECTION SAYS SO.  A line longer than a page
# used to make the data block two pages -- phase 40's MLBIGLINE marker, reached by
# three of the sixteen cases.  A record is a pointer, so there is no such thing any
# more, and the marker has no anchor in the output at all.  That is the one number
# that may go down.

# THE BODY IS GO: tools/go/internal/check/zero44.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero44-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero44-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero44 "$work" "$state"
