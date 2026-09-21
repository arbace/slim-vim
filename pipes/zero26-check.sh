#!/bin/sh
# Zero phase 26, the check -- the header types and macros the core can own.
# See pipes/zero26-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero26-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero26-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags, and `minmax.txt`,
# the two expansions read back out of <sys/param.h> through the preprocessor.
#
# WHAT IS CLAIMED, in seven parts:
#
#   ARITHMETIC  computed FROM THE INPUT: the eight names the core took from a header
#               are at 0 above the host block and at their own counts below it, the
#               eleven directives are where they were, the line count moved by exactly
#               the 24 lines the edit adds, and tools/canon.sh is a NO-OP.
#   THE CLOCK   THE ONLY THING THAT CHANGES CODE, stated as an equality: with the clock
#               ALONE reverted, the binary is `cmp`-IDENTICAL to the one the phase was
#               handed.  So the other six substitutions and the nine prototypes are
#               tier 1 of CLAUDE.md's verification table -- the same program -- and
#               only the clock has anything left to prove.
#   THE HEADERS the whole reason this phase comes BEFORE the move.  Sixteen
#               `static_assert`s compare every core-owned spelling against the header
#               type it replaces, and every one of them NAMES a header type, so not one
#               could be written after the move.  With a control that breaks one.
#   MISMATCHES  four deliberately wrong declarations, each of which the headers above
#               catch, and each named: conflicting types for time, for malloc, for
#               getpid, and the `static` trap.  They are the negative half of the same
#               property.
#   THE TAG     `struct timeval` with a TAG, which the brief calls a hard error.  It is
#               not, in this dialect, and the check says so with the measurement rather
#               than repeating the claim: silent under C23, `error: redefinition of
#               'struct timeval'` under -std=c11 and -std=c17.  Which is why the layout
#               is asserted in THE HEADERS and not left to a diagnostic.
#   SYMBOLS     `nm -u` is THE SAME SET, as a `comm` empty in BOTH directions, and
#               `main` is still the only external symbol.  A rename and a wrapper in
#               one translation unit free nothing and cost nothing.
#   BEHAVIOUR   the declared delta is NOTHING AT ALL.  Two full recordings, of the
#               binary this phase was handed and of its own, are BYTE-IDENTICAL -- and
#               the recording is NOT blind to what moved: a control whose
#               `musl_gettimeofday` writes the two fields the wrong way round moves six
#               of the 102 screen cases.  tools/zerodelta.sh is run by
#               tools/phaserun.sh after this check and is the second opinion.
#
# THE CONTROL IS SCREEN CASES AND NOT A WHOLE RECORDING, and that is a measurement
# about the harness rather than a shortcut.  A binary whose clock runs backwards has
# timeouts that never expire, so tools/zpty.py waits out its deadline, writes `stalled`
# and exits 1 -- correct behaviour on a deliberately broken editor, and two minutes of
# it.  Letting that exit status reach `set -e` would make a good control into a flaky
# check, so the control is `zcases` alone, which drives pipes, has its own
# per-case timeout and is where six of the seven measured differences were.
#
# AND `zhostonly`, WHOSE EXCEPTIONS THIS PHASE CHANGED.  The tool named `struct
# timeval` in the core twice -- "the clock's, not this phase's" -- and this is that
# phase, so both exceptions go; `kill` acquires one, because the core's call to it now
# has a prototype at file scope and the prototype is the same fact the tool already
# excepts inside vim_handle_signal.  An exception that stops being true is what the
# tool exists to notice, and it noticed.

# THE BODY IS GO: tools/go/internal/check/zero26.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/canon.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero26-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero26-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero26 "$work" "$state"
