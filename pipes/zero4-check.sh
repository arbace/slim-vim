#!/bin/sh
# Zero phase 4, the check -- Ex mode, silent mode and the four options are gone.
# See pipes/zero4-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero4-check.sh <work-dir> <state-dir>     (run from the repository root)
#
# Runs after pipes/zero4-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# built from the boundary's own makefile flags.
#
# THE DECLARED DELTA IS NOT THE WHOLE EVIDENCE HERE, for two reasons that pull in
# opposite directions.  `pipes/zero.delta` says six records move -- `key_Q`,
# `key_gQ` and the argv rows `-e`, `-E`, `-e -s`, `-v` -- and tools/zerodelta.sh
# proves that exactly those and nothing else did, against baselines recorded from
# whim-vim.  What it cannot show is a BEFORE: the baselines are one recording of one
# binary, so "the old one entered Ex mode and the new one beeps" is not a sentence
# it can say.  The probes below say it, by running both binaries.
#
# They are in two halves and both halves are the point:
#
#   MUST DIFFER   the six records above and a pty session, each required to show Ex
#                 mode on the OLD binary.  A probe that only checks the new binary
#                 passes just as well on a phase that did nothing.
#   MUST NOT      `-s` alone (already an unknown option before this phase, so it is
#                 not in the delta), every `+{command}` form, `:append`/`:insert`/
#                 `:change` (which read through getexline, not the Ex-mode reader),
#                 `:visual`/`:view`/`:vi`/`:ex` from Normal mode (whose Ex-mode
#                 escape this phase folded away), bare `-`, `--`, one and two file
#                 arguments, the three `-T` spellings, a plain edit and an editing
#                 pty session.
#
# A record is built the way `zcases` builds one and scrubbed the same way
# (tools/zrec.py): `mainerr()` prints the version banner, which carries __DATE__ and
# __TIME__, so two binaries built a minute apart disagree on stderr for a reason
# that is not the editor's behaviour -- which is exactly why `-s` reads as unchanged
# and must.

# THE BODY IS GO: tools/go/internal/check/zero4.go and tools/go/internal/check/zero4probes.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/phasecheck.sh
#   tools/st.sh
set -eu

work=${1:?usage: zero4-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero4-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero4 "$work" "$state"
