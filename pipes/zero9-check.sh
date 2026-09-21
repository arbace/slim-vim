#!/bin/sh
# Zero phase 9, the check -- nothing in the editor reads a byte any more.
# See pipes/zero9-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero9-check.sh <work-dir> <state-dir>     (run from the repository root)
#
# Runs after pipes/zero9-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from: the left-hand side of every
# before-and-after count, and the thing this check builds twice more.
#
# THE HONEST PROBLEM, AND WHAT IS DONE ABOUT IT.  There is no behavioural probe for
# this phase, and no dishonest one is offered instead.  `readfile()` was ALREADY
# unreachable when the phase was handed the tree -- phases 5 through 8 took the
# file argument, the bare `-`, and every command that could name a file -- so
# nothing this editor can be given reached it before the cut either, and every
# recording is byte-identical across the phase BY CONSTRUCTION.  A probe that
# "moved" would mean the phase was wrong.
#
# So the evidence is an INSTRUMENTED PAIR, built from the source the phase was
# handed, and it is the whole of what this phase can prove:
#
#   probe   old.c with `(void)write(2, "READFILE-ENTERED\n", 17);` as readfile()'s
#           first statement.  Recorded with tools/zrecord.sh: ZERO of the 106
#           records a recording held WHEN THIS PHASE WAS WRITTEN -- it is 122 since
#           zero phase 40 added the memline corpus, and the assertions below are
#           written against the count the run measures, not against that number --
#           records may carry the marker.  That is the claim -- on the binary this
#           phase was handed, nothing the instrument can do enters readfile().
#   ctl     old.c with the IDENTICAL instrument in open_buffer(), which IS reached.
#           104 of the same 106 records carry it.  That is the proof the probe can
#           fail: a marker written from a function the editor calls does arrive, in
#           the same recording, through the same grep.
#
# The two that do not carry it under `ctl` are ref-pty.txt and ref-term.txt, and
# the reason is the instrument and not the editor: both drive a real pty and keep
# what was DRAWN, where the other three keep stderr separately.  They are named
# here so that a third one going quiet would be a failure rather than a shrug.
#
# EIGHT ADVERSARIAL SESSIONS run on both instrumented binaries, and they are the
# part that asks whether anything could still get in: `:file /etc/hostname` and
# then `G`, an insert and an undo, `:bdelete`, `:new`, `:ball`, `:buffer 1`, and
# the `%` and `#` registers.  Naming a buffer after a real file that exists and
# then making the editor want its contents is the shape of every way back into
# `readfile()` there was.  Each must mark under `ctl` and must not under `probe`:
# a session that reaches neither proves nothing, and that is checked.
#
# AND THE RECORDINGS ARE COMPARED DIRECTLY, old binary against new, rather than
# only through .reference/zero-baselines: `diff -rq` over two full tools/zrecord.sh
# recordings, which is what "this phase declares nothing at all" means measured
# between the two binaries themselves.  tools/zerodelta.sh runs afterwards and says
# the same thing against whim-vim's frozen behaviour.
#
# SIX THINGS THE SOURCE MUST SAY, and the traps that make the obvious check wrong,
# are in sections 1 and 2.

# THE BODY IS GO: tools/go/internal/check/zero9.go and tools/go/internal/check/zero9evidence.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/enumvals.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero9-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero9-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero9 "$work" "$state"
