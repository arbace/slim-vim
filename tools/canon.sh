#!/bin/sh
# The canonicalisers, in their order, once or to a fixpoint.
#
# Usage: tools/canon.sh <file> [--once]
#
# THE WORK IS NOW GO.  This file is the entry point; the passes are
# tools/go/internal/canon/canon.go, which runs them in the same order with the
# same twenty-round ceiling and the same output lines.  Compared before the
# swap: 502 of 502 slim inputs identical, 494 of them exercising it, and one
# --once round over a 4.7 MB file went from 3.577s to 0.314s with byte-
# identical output.
#
# The order is load-bearing and lives with the code: brace after joinparens and
# splitheads, so a head is a whole line ending in ')' and a body starts on the
# next; forcomma after brace, because hoisting a statement in front of a `for`
# is only safe once every body is a brace block.  One pass is not enough, which
# is why there is a fixpoint: forcomma's hoist gives splitheads and brace
# something new to find, and onestmt splits one label off a
# `case A: case B: case C:` line per pass, so that line alone needs five.
#
# Exceeding twenty rounds is a hard failure and not a number to raise: two
# passes undoing each other is a bug in one of them.
#
# --once runs them a single time, for a caller with a fixpoint of its own:
# tools/sweep.sh loops until a whole round changes nothing and canon is part of
# that round, so proving canon settled separately would prove it twice.
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

file=${1:?usage: canon.sh <file> [--once]}
bin=$(tools/gobuild.sh)
if [ "${2:-}" = --once ]; then
    exec "./$bin" canon "$file" --once
fi
exec "./$bin" canon "$file"
