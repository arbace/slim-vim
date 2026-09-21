#!/bin/sh
# Zero phase 7, the check -- nothing can take bytes off a disk on request any more.
# See pipes/zero7-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero7-check.sh <work-dir> <state-dir>     (run from the repository root)
#
# Runs after pipes/zero7-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from, which is the left-hand side of every
# before-and-after count below.
#
# FIVE THINGS ARE PROVED HERE, and the third is the only one that can say what this
# phase is actually for.
#
# 1. THE CUT, which is the sweep's work and not the edit's.  Six functions go, none
#    of them named by the edit -- ex_read, do_bang, do_shell, do_filter,
#    check_secure and prevcmd_is_set -- with the static `prevcmd`, the struct field
#    `usefilter` the edit folded away, and five strings (`"read"`, E12, E34, E319
#    and E484).  Listing them here is a RECORDING of what the sweep did, which is
#    the only place a list of removed names belongs.
#
#    THE TRAPS, ALL MEASURED, that make a copied "every name at zero mentions" loop
#    the wrong check:
#      * `secure` IS NOT `check_secure`.  The function goes; the variable keeps
#        ELEVEN mentions, because `secure` is the vimrc/tag-search flag and half the
#        editor tests it.  Only the two inside check_secure() went.
#      * THE BARE WORD `read` SURVIVES three times -- two `read(fd, ...)` calls and
#        an E222 string -- and `readfile`, `read_buffer`, `read_edit`, `readonly`,
#        `shell` and `filter` all survive at their own counts.  This phase removes
#        `:read`, not reading.
#      * `E32: No file name` SURVIVES, still reachable through check_fname() from
#        do_ecmd(); `E484: Can't open file` does NOT -- ex_read was its last
#        speaker, and after this phase nothing in the file says it.  Both are
#        asserted, in opposite directions.
#
# 2. THE LINE AGAINST THE PHASE THAT STOPS READING A BYTE (ZERO-PLAN.md P8), stated
#    as counts so that taking any of it here would fail rather than widen quietly:
#    `readfile` is required to keep EXACTLY 5 mentions -- its prototype, its
#    definition and the three calls in read_buffer() and open_buffer() -- with
#    read_buffer at 17 and open_buffer at 6.  What this phase takes is the two calls
#    that were ex_read's.  The table is checked the same way: 104 rows, names()
#    reading exactly those, the static_assert in place, and the FOUR rows of margin
#    above create_cmdidxs's floor of 100 said out loud -- the `:edit` phase is the
#    one that must lower it (ZERO-PLAN.md 3a).
#
# 3. THE PROBES, on BOTH binaries, because THE CORPUS CANNOT SEE A FILE BEING READ.
#    Every one of `zcases`'s 102 cases types its own text and names no file:
#    `cmd_read` types `:read` with no file name, so the baseline it is compared
#    against records `E32: No file name` -- an editor that FAILED to read.  A
#    declared delta of "cmd_read and read_cmd_gone moved" is therefore consistent
#    with a phase that changed two error messages and left readfile() reachable from
#    a command.  So the probes run the binary this phase was handed beside the one
#    it made, and the ones that matter require the OLD binary to pull a file off the
#    disk and the new one to refuse.
#
#    THE FILE IS `keys` ITSELF.  tools/zstream.py writes a session's keystrokes into
#    a file called `keys` in the run directory and feeds it on stdin, so there is
#    always one file there to read and no runner has to plant one: `:r keys` reads
#    it back, and the old binary answers `"keys" [noeol] 1L, 33B` with the
#    keystrokes in the buffer.
#
# 4. THE INHERITANCE CHECK.  whim's Phase 80 gave every row its shortest
#    abbreviation and made a match require at least that many characters, so a
#    removed name cannot be inherited by the next row -- but that is an argument,
#    and `:r` silently becoming `:redo` is exactly the shape of bug CLAUDE.md
#    records for `:help` -> `:helpclose`.  Six spellings are typed and each must
#    answer E492 now and something else before; `:redo`, `:redraw`, `:registers`
#    and `:reg` are required not to move at all.
#
# 5. A REAL TERMINAL.  Every probe above went through a pipe.  The session types
#    `:r <file>` on a pty, where the file is one the RUNNER wrote -- the editor has
#    had no way to write one since phase 6 -- and the old binary puts its line in
#    the buffer while this one answers E492.  An ordinary editing session beside it
#    is required to be identical.
#
# WHAT IS NOT ASSERTED, and why.  `E319: Sorry, the command is not available in this
# version` is what whim's do_shell()/do_filter() stubs answered, so it never reaches
# a SNAPSHOT: the message is drawn, a `Press ENTER` prompt follows and the next
# redraw wipes the line before the cursor comes back, which is where
# tools/zscreen.py takes its picture.  It is in the STREAM, so that is where the
# probe looks -- and its presence on the old binary is also the proof that no shell
# ever ran, the stub having refused before one could.
#
# A record is built the way `zcases` builds one and scrubbed the same way
# (tools/zrec.py).  tools/zstream.py's session() is not called directly because this
# check needs the raw stream beside the screens.

# THE BODY IS GO: tools/go/internal/check/zero7.go and tools/go/internal/check/zero7probes.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero7-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero7-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero7 "$work" "$state"
