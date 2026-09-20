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
# Named here so tools/implhash.sh hashes the implementation into every phase's
# key -- implhash greps for paths and does not know what a comment is, the same
# mechanism the Python `import` comments use.  THE DIRECTORY, NOT A LIST OF
# FILES: a list is curated and drifts, and this one did -- it named 18 of 128
# .go files, four of which the sweep reaches (cutil/body.go, cutil/definition.go,
# cutil/split.go, canon/strings.go) were in no list, and `go` was not even in
# implhash's extension alternation, so editing the sweep moved no key at all
# while gobuild.sh built a different binary.  The patch is named too and must
# be: implhash follows two levels, sweep.sh is level 1 and gobuild.sh level 2,
# so the patch gobuild.sh names is level 3 and was never reached.
#
#   tools/go/                        every .go, go.mod and go.sum -- the binary
#   tools/patches/cc-v4-c23.patch    what the fork is built with

set -eu

f=${1:?usage: sweep.sh <file.c>}
bin=$(tools/gobuild.sh)
exec "./$bin" sweep "$f"
