#!/bin/sh
# Zero phase 39 -- `-T {term}` goes, and the command line is `+{command}` alone.
# See ZERO-GOAL.md.
#
# Usage: pipes/zero39-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# Zero phase 5 left argv as exactly two options: `+{command}`, which is how a host
# tells the editor what to do, and `-T {term}`, which is how a SHELL told it what it
# was attached to.  A core is told that by its host or not at all -- and `-T` has
# had a replacement inside the editor since before this pipeline began: `+set term=`
# reaches did_set_term() and does everything `-T` did, which is why zero phase 33
# rebuilt the terminal harness on it.  So this removes the option, and after it
# `+{command}` is the whole command line: every other word is what every unknown
# word already was, `mainerr(ME_UNKNOWN_OPTION)`.
#
# WHAT THE OPTION LETTER PULLS WITH IT, and every one of these is dead code a sweep
# CANNOT see -- gcc has no warning for a variable that is only ever FALSE, for a
# switch that has lost its cases, or for a statement after a `return`:
#
#   want_argument   the flag `-T` was the only setter of.  With no case left to set
#                   it the whole `if (want_argument)` block is unreachable, and that
#                   block is where ME_GARBAGE, mainerr_arg_missing() and the second
#                   switch -- `parmp->term = argv[0]` -- live.
#   the two rows    ME_GARBAGE and ME_ARG_MISSING lose their last use, and
#                   main_errors[] is INDEXED BY THEM, so the enumerator and the row
#                   are one thing.  deadenums.py would take the enumerator and leave
#                   the row, and the rows are positional; this is CLAUDE.md's
#                   deadfields lesson in a table, so the edit takes both and
#                   renumbers what is left.  mainerr_arg_missing() goes with them
#                   because it is ME_ARG_MISSING's only other mention: the
#                   enumerator cannot go while its one reader is still there.
#   mparm_T.term    the field nothing assigns now.  It goes in the EDIT for a
#                   reason phase 38's dead clause did not have: deadfields.py
#                   matches by NAME, and this file holds thirty-two mentions of
#                   another struct's `.term` member (attr_entry's `ae_u.term`), so
#                   that tool can never see this one dead.  The edit computes that
#                   partition rather than asserting it.
#   termcapinit()   it can only ever be handed what the memset left, so it takes no
#                   name at all now and the compiled default -- read out of the
#                   function, not written here -- is its initialiser.  That is
#                   pipes/zero13-edit.sh's ui_write(console) again.
#
# AND THEN set_termname()'s NO-SCREEN ARM CANNOT RUN.  set_termname() has two call
# sites, and the edit partitions them: termcapinit()'s, which reaches it before
# there is a screen, and did_set_term()'s, which is `:set term=` at run time.  The
# first can no longer fail -- the compiled default IS a row of builtin_terminals[],
# which the edit checks -- so when find_builtin_term() answers nullptr the call came
# from the second, where `starting` is NO_BUFFERS or 0 and never NO_SCREEN (the edit
# reads every assignment to `starting` and requires none of them to be NO_SCREEN).
# So `if (starting != NO_SCREEN)` is always true there, the block returns FAIL, and
# the three statements after it are unreachable: the fallback that phase 38 had to
# repair, report_default_term(), and the option write that recorded it.
# pipes/zero39-check.sh measures all of that with the same marker in the same place
# on both texts -- the input enters the fallback in exactly the two `-T` records and
# a control built from THIS phase's output enters it in none.
#
# THE MESSAGE GOES WITH THE FALLBACK, for phase 38's reason read backwards.  That
# phase retargeted `' not known, defaulting to 'xterm''` onto the name it kept
# because nothing in the build checks that a message tells the truth.  There is no
# fallback to name now, so the clause that promised one is cut -- the NAME is read
# out of the assignment this edit deletes, never written here -- and what is left is
# `'vt320' not known`, which is true, with E522 following it exactly as before.
#
# WHAT RIDES ALONG IS `requested` AND NOT THE 256-COLOUR TEST, and the difference is
# the whole of what was measured.  set_termname() keeps the name it was GIVEN in
# `requested` for one test, `musl_strstr(requested, "256color")`, and CLAUDE.md says
# why: the unknown-terminal path reassigned `term`, so testing that would have given
# `alacritty-256color` eight colours.  That path is what this phase removes, so the
# only rewrite of `term` left is the `term += 8` that strips a `builtin_` prefix --
# and a strstr cannot match inside that prefix, because the needle begins with a
# character the prefix does not contain, which the edit checks rather than asserts.
# So `requested` IS `term` for this test and the variable goes.
#
# THE TEST ITSELF DOES NOT FOLD, and this phase declines to pretend it does.  Both
# surviving terminal names disagree on it -- `xterm-256color` matches and `debug`
# does not -- and `:set term=` still names either at run time.  MEASURED, in both
# directions, and the check keeps the measurement: with the name test forced TRUE
# exactly ONE of the nineteen rows moves (`debug` gains t_Co=256) and with it forced
# FALSE EIGHTEEN move (everything the compiled default reaches drops to t_Co=8).
# A fold either way would be a behaviour change, so there is none here.
#
# THE INPUT BINARY AND ITS ENUMERATOR VALUES ARE TAKEN HERE, before the edit, as
# pipes/zero5-edit.sh takes them: the check needs the old binary to show what `-T`
# used to do, and the DWARF dump because main_errors[] is indexed by enumerators
# this phase renumbers and a build is perfectly happy to renumber a table index.
set -eu

work=${1:?usage: zero39-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero39-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && SOURCE_DATE_EPOCH=0 gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

# The enumerator values of the text this phase is HANDED: main_errors[] is indexed
# by them and this phase moves one, so the check compares DWARF and not the build.
tools/enumvals.sh "$f" "$state/enums-before" &
pid_enums=$!

tools/st.sh edit zero39 "$f"

# NOT create_cmdidxs --check, for pipes/zero2-edit.sh's reason: the derived
# first-two-letters index went with the command table whim reduced, and the tool
# raises rather than reporting nothing.  Nothing here touches the command table.
#
# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  cmdline      the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
wait $pid_enums || { echo "  cmdline      the input's enumerator values could not be dumped"; exit 1; }
echo "  cmdline      the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from and $(grep -c '' "$state/enums-before") enumerator values: this phase moves command lines and renumbers a table index, and both need a before"

# tools/phaserun.sh sweeps next, then runs pipes/zero39-check.sh.
