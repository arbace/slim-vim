#!/bin/sh
# Zero phase 6, the check -- nothing can put bytes on a disk any more.
# See pipes/zero6-edit.sh, and ZERO-GOAL.md.
#
# Usage: pipes/zero6-check.sh <work-dir> <state-dir>     (run from the repository root)
#
# Runs after pipes/zero6-edit.sh and the sweep tools/phaserun.sh runs between them,
# and reads nothing from the edit's shell -- only the work tree and the state
# directory.  What the edit left there is `old`, the binary this phase was HANDED,
# and `old.c`, the source it was built from, which is the left-hand side of every
# before-and-after count below.
#
# FIVE THINGS ARE PROVED HERE, and the third is the only one that can say what this
# phase is actually for.
#
# 1. THE CUT, which is the sweep's work and not the edit's.  Nineteen functions go,
#    none of them named by the edit: ex_write, ex_update, ex_exit, do_write,
#    check_writable, check_overwrite, not_writing, check_readonly,
#    check_file_readonly, buf_write, buf_write_bytes, check_mtime, time_differs,
#    write_eintr, vim_fexists, mch_setperm, mch_fsetperm, mch_nodetype and
#    u_update_save_nr, with one struct field (exarg_T.append) and fourteen
#    enumerators.  Listing them here is a RECORDING of what the sweep did, which is
#    the only place a list of removed names belongs.
#
#    TWO TRAPS, BOTH MEASURED, that make a phase-4-style "every name at zero
#    mentions" loop the wrong check:
#      * `check_readonly` is ALSO A LOCAL, in readfile() -- `int check_readonly;`
#        and three uses.  After this phase `grep -cw` is 4, not 0, and a loop that
#        wanted 0 would fail on a correct phase.  What must be gone is the
#        DEFINITION, `^check_readonly(`, and the four survivors must all be inside
#        readfile(), which is asserted rather than assumed.
#      * `"write"` SURVIVES, as the name of the 'write' option, and `E32: No file
#        name` survives with it, still reachable through check_fname() from
#        do_ecmd() and ex_bang().  A "no mention of write anywhere" check would fail
#        on a correct phase just as surely.
#
# 2. THE TABLE.  105 rows, create_cmdidxs.names() reading exactly those, the
#    static_assert still there, and the five rows of margin above the tool's floor
#    of 100 said out loud -- the :edit phase is the one that must lower it
#    (ZERO-PLAN.md 3a).
#
# 3. THE PROBES, on BOTH binaries, because THE CORPUS CANNOT SEE WRITING.  Every
#    one of `zcases`'s 102 cases types its own text and never names a file:
#    `cmd_write` types `:write` with no file name, so the baseline it is compared
#    against records `E32: No file name` -- an editor that FAILED to write.  A
#    declared delta of "cmd_write and zz_key moved" is therefore consistent with a
#    phase that changed one error message and left buf_write() reachable.  So the
#    probes run the binary this phase was handed beside the one it made, in a
#    directory they KEEP, and the six that matter require the old binary to leave a
#    file on the disk and the new one to leave none.
#
# 4. THE INHERITANCE CHECK.  whim's Phase 80 gave every row its shortest
#    abbreviation and made a match require at least that many characters, so a
#    removed name cannot be inherited by the next row (ZERO-PLAN.md 3a) -- but that
#    is an argument, and `:w` silently becoming `:winsize` is exactly the shape of
#    bug CLAUDE.md records for `:help` -> `:helpclose`.  Eight spellings are typed
#    and each must answer E492 now and something else before.
#
# 5. A REAL TERMINAL.  `:wq` on a pty is how a person leaves this editor, and every
#    probe above went through a pipe.  The session is run on both binaries: the old
#    one writes the file and exits, the new one answers E492 and writes nothing.
#    pipes/zero2-check.sh drives a pty with `:wq` and reads the file back too, and
#    pipes/zero.stages says why that needs no `apart 2 6`: it opens the file as an
#    ARGUMENT and phase 5 already made that an unknown option, so it never reaches
#    the `:wq` -- measured identically on a phase 5 and a phase 6 tree.
#
# A record is built the way `zcases` builds one and scrubbed the same way
# (tools/zrec.py), with one section added: the files the run left behind.
# tools/zstream.py's session() throws its directory away, which is the one thing a
# phase about writing files cannot do, so the runner is here.

# THE BODY IS GO: tools/go/internal/check/zero6.go and tools/go/internal/check/zero6probes.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero6-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero6-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero6 "$work" "$state"
