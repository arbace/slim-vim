#!/bin/sh
# Run one slimtools subcommand.
#
# Usage: tools/st.sh <subcommand> [args]      (run from the repository root)
#
# This is the third wrapper of its kind and it exists for the same reason as the
# sweep's and the canonicalisers': a phase program names a PATH, and that path is
# what implhash hashes.  A phase that ran the Go binary directly --
# `bin=$(tools/gobuild.sh); ./"$bin" nomouse f.c` -- would name the builder and
# NOT the implementation, because the builder says `find tools/go` and
# `cd tools/go`, neither of which carries the trailing slash implhash's directory
# rule needs.  Measured: the Go sources would reach a split phase's key by way of
# the sweep, and no whole-program phase's key at all.  So the wrapper names the
# directory itself, once, here.
#
# WHY A WRAPPER AND NOT A LONGER CALL AT EVERY SITE.  It is one token per call
# site -- `python3 tools/<cutter>.py f.c` becomes `tools/st.sh <cutter> f.c` --
# which keeps a swap reviewable as a one-line diff and reversible per tool.  It
# also costs nothing: the builder warm is 16 ms, against 20 ms for python3 to
# import the shared cutter library alone, so the wrapper is cheaper than what it
# replaces before the subcommand has run at all.
#
# NOTHING ELSE IS NAMED HERE ON PURPOSE, and that is not tidiness.  implhash
# greps for paths and cannot tell "I depend on X" from "I am talking about X", so
# a path written into this comment enters the key of every phase that calls this
# wrapper.  The first draft explained itself by naming five other tools and
# charged all five to all of them -- a cutter's bytes would have re-keyed phases
# that never call it.  Refer to a tool by what it does, not by its path, unless
# running it is the reason this file exists.
#
# The two that ARE the reason, named so implhash hashes the implementation into
# every phase's key:
#
#   tools/go/                       the whole toolset; the directory and not a
#                                   list of files, because the build keys the
#                                   binary on every file under it
#   tools/patches/cc-v4-c23.patch   the build's other input
set -eu

[ $# -gt 0 ] || { echo "usage: tools/st.sh <subcommand> [args]" >&2; exit 2; }

bin=$(tools/gobuild.sh)
exec "./$bin" "$@"
