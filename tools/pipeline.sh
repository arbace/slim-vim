# The two pipelines, and the only place that knows how they differ.
#
# Sourced, not run:  . tools/pipeline.sh [slim|whim|zero]
#
#   slim-vim.c = F(upstream@sha)     SLIM-GOAL.md, ten phases, work in upstream/
#   whim-vim.c = G(slim-vim.c)       WHIM-GOAL.md, work in whim/
#   zero-vim.c = H(whim-vim.c)       ZERO-GOAL.md, work in zero/
#
# Both are the same construct -- a phase is a function of the tree it is handed,
# memoized in three tiers -- so the driver, the boundaries, the oracle and the
# synthesiser are shared and this file is the whole of the parameterisation.
# A second copy of memo.sh would be a second place for the memoize to be
# subtly wrong.
#
# The boundary tag differs (p0..p9, q0.., r0..) so that one .cache/ can hold
# all three without a key collision, and so that a stray p3 in a whim build is
# obviously wrong rather than plausibly right.
#
# PSOURCE is the one file a sweep runs on, which is what lets tools/phaserun.sh
# run a split phase's sweep itself.  slim has none: its phases work on a tree.
#
# PDELTA is the checker a stage's declared delta goes through, when
# pipes/<pipeline>.delta exists: tools/phaserun.sh runs it and tools/implhash.sh
# hashes it.  Each pipeline's delta is against its own baselines, so each has its
# own checker; slim has no delta.
#
# ZERO'S PHASE LIST IS NOT WRITTEN HERE, and that is measured rather than tidy.
# This file is hashed into every whim stage's key and every whim edit's (it is
# named by tools/phaserun.sh, which every split phase's key reads), so a byte
# changed here re-keys all of whim: 12 stages and 82 edits.  A zero phase list
# written here would do that every time a zero phase is added.  It is the
# `phases` line of pipes/zero.stages instead, which no key reads.

case ${1:-slim} in
    slim) PIPE=slim; TAG=p; IMPL=slim ; DOC=SLIM-GOAL.md
          PWORK=upstream; PBUILD=.build-slim; PSOURCE=; PDELTA=
          PHASE_LIST="0 1 2 3 4 5 6 7 8 9 10 11" ;;
    whim) PIPE=whim; TAG=q; IMPL=whim;  DOC=WHIM-GOAL.md
          PWORK=whim;     PBUILD=.build-whim; PSOURCE=whim-vim.c; PDELTA=tools/whimdelta.sh
          PHASE_LIST="0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82" ;;
    zero) PIPE=zero; TAG=r; IMPL=zero;  DOC=ZERO-GOAL.md
          PWORK=zero;     PBUILD=.build-zero; PSOURCE=zero-vim.c; PDELTA=tools/zerodelta.sh
          PHASE_LIST=$(awk '$1 == "phases" { $1 = ""; sub(/^ +/, ""); print }' pipes/zero.stages) ;;
    *)    echo "pipeline: no such pipeline: $1" >&2; return 1 2>/dev/null || exit 1 ;;
esac
