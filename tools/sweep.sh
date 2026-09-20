#!/bin/sh
# Delete what the cut left unreachable, to a fixpoint -- all six kinds, with
# the canonicalisers as the seventh member of every round.
#
# Usage: tools/sweep.sh <file.c>      (run from the repository root)
#
# THE WORK IS NOW GO.  This file is the entry point the phase programs name and
# nothing else: it builds tools/go and hands the file to `slimtools sweep`,
# which is tools/go/internal/sweep/sweep.go.  The shell version it replaces is
# in this repository's history, and the two were compared before the swap --
# the same report line for line, including the skip cache's `passed this text
# already` entries, and the same swept bytes.
#
# What the Go does differently is not what it computes but how often it pays
# for the file: the shell ran thirteen programs a round, each re-reading and
# rewriting a multi-megabyte file, and the Go reads once, transforms in memory,
# and writes twice -- for deadsweep, which asks gcc about the file, and
# deadenums, which asks tools/enumvals.sh.  Measured on zero42's unswept
# output, 79,380 lines: 15.675s became 8.353s and the output was identical.
# What is left is gcc, which neither version can avoid.
#
# The tools it runs are these, and they are named here so that
# tools/implhash.sh still hashes them into every phase's key -- implhash greps
# for paths and does not know what a comment is, which is the same mechanism
# the Python `import` comments use:
#
#   tools/go/internal/sweep/sweep.go     the loop, the skip cache, the ceiling
#   tools/go/internal/sweep/tools.go     the seven members of a round
#   tools/go/internal/dead/deadsweep.go  tools/go/internal/dead/deadprotos.go
#   tools/go/internal/dead/typereach.go  tools/go/internal/dead/funcreach.go
#   tools/go/internal/dead/deadfields.go tools/go/internal/dead/deadenums.go
#   tools/go/internal/canon/canon.go     tools/go/internal/cutil/blank.go
#   tools/enumvals.sh                    the DWARF dump deadenums asks for
set -eu

f=${1:?usage: sweep.sh <file.c>}
bin=$(tools/gobuild.sh)
exec "./$bin" sweep "$f"
