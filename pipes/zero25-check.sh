#!/bin/sh
# Zero phase 25, the check -- the plain host calls.
# See pipes/zero25-edit.sh, and ZERO-PLAN.md 4c.
#
# Usage: pipes/zero25-check.sh <work-dir> <state-dir>    (run from the repository root)
#
# Runs after pipes/zero25-edit.sh and the sweep tools/phaserun.sh runs between them, and
# reads nothing from the edit's shell -- only the work tree and the state directory.
# What the edit left there is `old.c`, the source this phase was HANDED, and `old`, that
# source built with SOURCE_DATE_EPOCH=0 and the boundary's own flags.
#
# THE BINARY IS NOT BYTE-IDENTICAL AND THIS CHECK DOES NOT ASK FOR IT.  Phases 23 and 24
# rested on `cmp`, which is tier 1 of CLAUDE.md's verification table; this phase cannot,
# because an indirect call through a function pointer and a direct call are different
# instructions at -O0 and removing two file-scope objects moves everything after them.
# MEASURED: the same 788,488 bytes, 347,279 of them differing.  So this phase goes back
# to the evidence every zero phase before 23 used -- A RECORDING -- with a control for
# EACH of the two names it makes direct, because "the recording did not move" is only
# worth something if a change at those two sites would move it.
#
# WHAT IS CLAIMED, in seven parts:
#
#   ARITHMETIC  computed FROM THE INPUT and not written here: `vim_host_exit` 3 -> 0 and
#               `vim_host_message` 10 -> 0, `host_exit` 2 -> 3 and `host_message` 2 ->
#               10, `exit_fn` and `message_fn` 2 -> 0, five lines fewer, the eleven
#               #includes where they were, cmdnames[] 98 and options[] 107 unmoved, and
#               tools/canon.sh a NO-OP on the output.
#   THE ORDER   the prototype is above every call and the definition below every one of
#               them, BY LINE NUMBER -- which is what makes the declaration load-bearing
#               and what will keep it serving when a later phase moves the definitions
#               further down.  The control is the output with the two prototype lines
#               DELETED, which must not compile.
#   LINKAGE     THE ASSERTION THAT MATTERS MOST.  `nm --extern-only --defined-only` is
#               still exactly `main`, and two controls say what the alternative was: with
#               `static` off the two PROTOTYPES gcc REFUSES -- `static declaration of
#               'host_exit' follows non-static declaration` -- and with it off the
#               prototypes AND the definitions the build is SILENT and `nm` prints
#               `host_exit` and `host_message` beside `main`.  That second one is the
#               mistake this phase could have made without anything else noticing.
#   SYMBOLS     `nm -u` is THE SAME SET, as a `comm` empty in BOTH directions.  This
#               phase frees NOTHING and says so as an equality: `exit` does not come
#               back, because the host's definition still does not call it -- phase 19's
#               __builtin_longjmp launcher is untouched.
#   THE BINARY  the same SIZE and NOT the same bytes, both stated as measurements.
#   THE RECORD  two full tools/zrecord.sh recordings, `diff -r` empty, with one control
#               per name: `host_code = r;` -> `r + 1` in host_exit moves 105 of the 106
#               records, and host_message's `write(err ? 2 : 1, ...)` with the streams
#               swapped moves 24 of the 30 command lines AND NOTHING ELSE -- which is
#               phase 21's own finding, that everything reaching host_message is a
#               message printed before there is a screen.
#   STRUCTURE   `zhostonly`, phase 20's structural check, still passes.  Renaming
#               nine call sites cannot disturb it -- `host_exit` and `host_message` are
#               not in its vocabulary, which is libc's terminal and signal names -- and
#               a phase that moves host calls about is exactly the one that should say so
#               rather than assume it.

# THE BODY IS GO: tools/go/internal/check/zero25.go, run through tools/st.sh.
# The tools it runs, named as PATHS so tools/implhash.sh hashes them into
# this phase's key -- a path the program does not name is a dependency no key
# sees.  Do not delete these lines.
#   tools/canon.sh
#   tools/phasecheck.sh
#   tools/st.sh
#   tools/zrecord.sh
set -eu

work=${1:?usage: zero25-check.sh <work-dir> <state-dir>}
state=${2:?usage: zero25-check.sh <work-dir> <state-dir>}
exec tools/st.sh check zero25 "$work" "$state"
