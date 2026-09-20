#!/bin/sh
# Zero phase 5 -- the command line is `+{command}` and `-T {term}`.  See ZERO-GOAL.md.
#
# Usage: pipes/zero5-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# A core is handed its buffer by a host, not by a shell.  What is left of
# `command_line_scan()` after phases 2 and 4 is five things -- `+cmd`, `-T`, a bare
# `-`, `--` and a file argument -- and the last three are the three that name a
# FILE or a STREAM to edit.  They go, and argv ends as exactly two options: the
# commands to run and the terminal to assume.  Everything else is what every other
# unknown word already was, `mainerr(ME_UNKNOWN_OPTION)`.
#
# WHAT GOES, in the parser:
#   * the file-argument branch -- the `else` arm: the ME_TOO_MANY_ARGS guard,
#     `parmp->edit_type = EDIT_FILE`, the `vim_strsave()` and the `buflist_add()`
#     that put the name in the buffer list.  The arm is REPLACED by
#     `mainerr(ME_UNKNOWN_OPTION)` rather than deleted: with no arm at all a bare
#     word matches neither `+` nor `-`, `argv[0][argv_idx]` is not NUL, and the
#     `while` never advances -- an infinite loop, not an error.
#   * `case NUL`, the bare `-`: EDIT_STDIN, `read_cmd_fd = 2` and its own
#     ME_TOO_MANY_ARGS guard.  It falls to `default:`, so `-` is an unknown option.
#   * `case '-'`, which is where `--` ended the options, with `had_minmin` and the
#     two `&& !had_minmin` tests that read it.  `--foo` already went to
#     ME_UNKNOWN_OPTION from inside that case and goes there from `default:` now;
#     what changes is `--` itself, which used to mean "every word after this is a
#     file name" and now means nothing.
#   * `ME_TOO_MANY_ARGS`, whose two call sites were exactly those two branches, and
#     its row in `main_errors[]`.
#
# THE ENUMERATOR IS THE ROW INDEX, so the two go together and the survivors
# renumber: `main_errors[n]` is what `mainerr(n)` prints, ME_ARG_MISSING moves 2->1,
# ME_GARBAGE 3->2 and ME_EXTRA_CMD 4->3.  That is the renumbering CLAUDE.md warns
# about, done deliberately -- the table and the enum are edited from one parse of
# both, and pipes/zero5-check.sh compares the DWARF enumerator values of the binary
# this phase was handed with the ones it made and requires exactly those three to
# have moved.  The dump of the input is taken HERE, in the background, because after
# the edit there is nothing left to dump it from.
#
# `main_errors[]` has SIX rows and had five enumerators; the sixth, "Invalid
# argument for", is unreachable already and was before this phase -- nothing names
# index 5.  It is whim's leftover, not this phase's, and it stays: this phase
# removes the row an enumerator it removes points at, and nothing else.
#
# WHAT `params.edit_type` THEN IS.  Nothing assigns it, so it is EDIT_NONE for
# ever, and its two readers in vim_main2() fold: `== EDIT_STDIN` never, which takes
# `read_stdin()`'s only call with it, and `!= EDIT_STDIN` always, which keeps
# `newline_on_exit` under the two conditions that were already there.  The field,
# the three EDIT_* enumerators, `read_stdin()` and `buflist_add()` are then what the
# sweep takes -- tools/deadfields.py for the field (there is no ml_recover() in this
# file, so a struct is no longer a disk format), deadenums.py for the three
# single-constant enums, each with an explicit value so nothing renumbers, and
# deadsweep.py for the two functions and whatever they orphan.
#
# WHERE THE LINE IS AGAINST THE LATER PHASES, and why it is there:
#   * `readfile()`'s stdin half -- its `read_stdin` PARAMETER and the arms that read
#     it, in readfile(), read_buffer() and open_buffer() -- is the "nothing reads a
#     byte" phase's (ZERO-PLAN.md P8).  This phase removes the FUNCTION
#     `read_stdin()`, which is argv's entry point into that code; the parameter's 23
#     mentions are asserted UNCHANGED, so a phase that took them here would fail.
#   * `read_cmd_fd` keeps its definition and its twelve remaining mentions.  Nothing assigns it
#     now, so it is 0 for ever and folding it is the stdin phase's; a file-scope
#     static that is read and never written draws no warning, so the sweep will not
#     touch it either way.  Only the assignment was argv's.
#   * the buffer's NAME is the "buffer has no name" phase's (P9).  Nothing here
#     touches `b_ffname`, `b_sfname` or `b_fname`: what goes is the one call that
#     ever gave the startup buffer a name from argv.  `create_windows()` already
#     opens an unnamed buffer when argv named none -- that is the `(none)` row of
#     `zargv` -- so the startup path is the one that was always there.
#
# WHAT IS KEPT, and asserted by name in the check: `+{command}` with MAX_ARG_CMDS
# and ME_EXTRA_CMD; `-T {term}` with want_argument, ME_GARBAGE and
# mainerr_arg_missing; ME_UNKNOWN_OPTION as the answer to everything else;
# `exe_commands()` and the `+cmd` execution path; and `'paste'`, which every case of
# the corpus seeds itself with (ZERO-PLAN.md 2d).
#
# THERE IS NO usage() TO LEAVE ALONE.  The brief warns that the help text may still
# advertise options that no longer exist; in this file it does not exist either --
# `grep -i usage zero-vim.c` finds nothing, whim having removed it, and `--help` is
# already `Unknown option argument: "--help"` in .reference/zero-baselines/
# ref-argv.txt.  Nothing here prints a list of options to keep true.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, exactly as pipes/zero2-edit.sh and pipes/zero4-edit.sh do it: the check
# requires the OLD binary to open the file and the new one to refuse, which is the
# difference between a probe and a formality.
set -eu

work=${1:?usage: zero5-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero5-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

# The enumerator values of the text this phase is HANDED.  It has to be taken
# before the edit, and it is the left-hand side of the check's renumbering proof.
tools/enumvals.sh "$f" "$state/enums-before" &
pid_enums=$!

tools/st.sh edit zero5 "$f"

# NOT create_cmdidxs --check, for pipes/zero2-edit.sh's reason: the derived
# first-two-letters index went with the command table whim reduced, and the tool
# raises rather than reporting nothing.  Nothing here touches the command table.
#
# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  noargv       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
wait $pid_enums || { echo "  noargv       the input's enumerator values could not be dumped"; exit 1; }
echo "  noargv       the input is $state/old, $(stat -c%s "$state/old") bytes, and $(grep -c '' "$state/enums-before") enumerator values, for the check's before-and-after"

# tools/phaserun.sh sweeps next, then runs pipes/zero5-check.sh.
