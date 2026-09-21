#!/bin/sh
# Zero phase 5, the check -- argv is `+{command}` and `-T {term}`, and nothing else.
# See pipes/zero5-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero5-check.sh <work-dir> <state-dir>     (run from the repository root)
#
# Runs after pipes/zero5-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `enums-before`, that binary's DWARF enumerator values.
#
# FOUR THINGS ARE PROVED HERE, and only the first is a grep.
#
# 1. THE CUT.  Six identifiers at zero mentions, the two strings that went with
#    them, and -- against the phases that come after -- `read_stdin`'s 23 remaining
#    mentions, every one of them the PARAMETER that the "nothing reads a byte"
#    phase owns, and `read_cmd_fd`'s twelve, which the same phase owns.  A phase
#    that reached past its own boundary would fail here rather than quietly widen.
#
# 2. THE RENUMBERING.  `main_errors[]` is indexed by the ME_* enumerators, so
#    removing ME_TOO_MANY_ARGS moves the three after it.  That is exactly what
#    CLAUDE.md says a build is perfectly happy to do wrongly, so it is checked
#    against DWARF and not against the build: every enumerator in the binary this
#    phase was handed must be in the one it made with the same value, except
#    ME_TOO_MANY_ARGS and the three EDIT_*, which must be gone, and ME_ARG_MISSING,
#    ME_GARBAGE and ME_EXTRA_CMD, which must each be exactly one lower.  There are
#    1,327 of them and a wrong table index would not show up anywhere else.
#
# 3. THE PROBES, in two halves, run on BOTH binaries.  The declared delta
#    (tools/zerodelta.sh) says exactly six of the 30 command lines moved and
#    nothing else did, against baselines recorded from whim-vim -- but the
#    baselines are one recording of one binary, so they cannot say "the old one
#    opened the file".  These say it:
#
#      MUST DIFFER   a file argument, two file arguments, a bare `-` with text on
#                    stdin, `--`, `-- +q!` and `+q! f.txt`, each also required to
#                    show the OLD behaviour on the OLD binary -- a probe that only
#                    looks at the new binary passes on a phase that did nothing.
#      MUST NOT      every `+{command}` form including `+set paste`, the three `-T`
#                    spellings and an unknown terminal name, the options that were
#                    already unknown, an ordinary keystroke edit, and a pty session.
#
# 4. THE INSTRUMENT SWAP, which this phase is the cause of.  termcheck is
#    whim's, and it asks its question with a file argument.  From this boundary on
#    that is an unknown option and all nineteen of its rows read `(none)` -- so
#    zero's recording now uses `ztermcheck`, which is termcheck.py with its
#    ask() replaced and nothing else.  Both halves are measured here: the new tool
#    records the baseline's nineteen rows byte for byte from the binary this phase
#    was handed, and the old tool records nothing but `(none)` from the one it made.
#
# A record is built the way `zcases` builds one and scrubbed the same way
# (tools/zrec.py): mainerr() prints the version banner, which carries __DATE__ and
# __TIME__, so two binaries built a minute apart disagree on stderr for a reason
# that is not the editor's behaviour.

# THE BODY IS GO: tools/go/internal/check/zero5.go and tools/go/internal/check/zero5probes.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/enumvals.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero5-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero5-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero5 "$work" "$state"
