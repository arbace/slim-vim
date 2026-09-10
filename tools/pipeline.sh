# The two pipelines, and the only place that knows how they differ.
#
# Sourced, not run:  . tools/pipeline.sh [slim|pure]
#
#   slim-vim.c = F(upstream@sha)     SLIM-GOAL.md, ten phases, work in upstream/
#   pure-vim.c = G(slim-vim.c)       PURE-GOAL.md, work in pure/
#
# Both are the same construct -- a phase is a function of the tree it is handed,
# memoized in three tiers -- so the driver, the boundaries, the oracle and the
# synthesiser are shared and this file is the whole of the parameterisation.
# A second copy of memo.sh would be a second place for the memoize to be
# subtly wrong.
#
# The boundary tag differs (p0..p9 against q0..) so that one .cache/ can hold
# both without a key collision, and so that a stray p3 in a pure build is
# obviously wrong rather than plausibly right.

case ${1:-slim} in
    slim) PIPE=slim; TAG=p; IMPL=slim ; DOC=SLIM-GOAL.md
          PWORK=upstream; PBUILD=.build
          PHASE_LIST="0 1 2 3 4 5 6 7 8 9" ;;
    pure) PIPE=pure; TAG=q; IMPL=pure;  DOC=PURE-GOAL.md
          PWORK=pure;     PBUILD=.build-pure
          PHASE_LIST="0 1" ;;
    *)    echo "pipeline: no such pipeline: $1" >&2; return 1 2>/dev/null || exit 1 ;;
esac
