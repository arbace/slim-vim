# The pipeline's parameters.  Sourced, not run:  . tools/pipeline.sh slim
#
#   slim-vim.c = F(upstream@sha)     SLIM-GOAL.md, twelve phases, work in upstream/
#
# The memoize driver, the oracle, the synthesiser and the verifier take the
# pipeline as an argument and read it from here.  There was a time this file
# held three: the whim and zero pipelines, which take slim-vim.c as their input,
# moved to github.com/arbace/go-whim with the Go toolset they run, and the
# parameterisation stays because it costs nothing and keeps the driver honest
# about which of its facts are slim's.
#
# PSOURCE is the one file a split phase's sweep runs on and PDELTA the checker
# of a declared delta; slim has neither.

case ${1:-slim} in
    slim) PIPE=slim; TAG=p; IMPL=slim ; DOC=SLIM-GOAL.md
          PWORK=upstream; PBUILD=.build-slim; PSOURCE=; PDELTA=
          PHASE_LIST="0 1 2 3 4 5 6 7 8 9 10 11" ;;
    *)    echo "pipeline: no such pipeline: $1" >&2; return 1 2>/dev/null || exit 1 ;;
esac
