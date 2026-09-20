#!/bin/sh
# Whim phase 80 -- the Ex command table, cut to the commands that exist.
# See WHIM-GOAL.md.
#
# Usage: pipes/whim80-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# 600 rows in `enum CMD_index` and `cmdnames[]`, and 489 of them are ex_ni or
# ex_script_ni: every phase that removed a command pointed its row at the stub and
# left the row, because the row still did one job -- it held the command's NAME, and
# a name in the table decides what every abbreviation of every other name means.
# Delete `buffer` and `:b` means something else.  So the rows stayed, and with them
# the two-level prefix index generated from them.
#
# THIS PHASE DELETES THE ROWS AND KEEPS WHAT THEY WERE FOR.  The lookup used to be
# "the first row, in table order, whose name starts with what was typed", so a
# name's shortest abbreviation was implied by every row above it.  Measured on q79:
# removing the 489 rows in place would have handed 15 prefixes that used to hit a
# stub to a live command -- :n to nmap, :o to omap, :h to highlight, :sa to saveas,
# :la to later, :en to enew, :ve to verbose.  No live command would have lost an
# abbreviation or gained another's, but an error becoming a mapping listing is not
# a thing to do to anyone.
#
# So each surviving row CARRIES its shortest abbreviation, computed here from the
# 600-row table before a row is touched, in the field that held the name's length
# (whose one reader was the Vim9 whole-name check, dead since phase 79).  A typed
# word names a command when it is a prefix of the name and at least that long.
# That makes a match unique, which makes row order irrelevant, which makes the
# index pointless: cmdidxs1, cmdidxs2, command_count and E943 go, and the lookup is
# a scan of 111 rows.  Every typed word resolves exactly as it did.  That is PROVED
# in step 1 rather than argued: the old lookup, index and all, and the new one are
# both modelled over every prefix of every one of the 600 names, and they must
# agree wherever the old answer survives and find nothing wherever it did not.
# Then step 9 runs every one of those words through both BINARIES.
#
# WHAT GOES WITH THE ROWS, each proved dead by the rows going:
#
#   26 CMD_ tests of commands that no longer exist (wincmd, if/endif, try, the
#       filename-escaping exceptions for grep/make/terminal, new/split/sview in
#       do_exedit, the Vim9 final/horizontal/mode quirks, and the index's two start
#       points CMD_Next and CMD_bang);
#   the `ni` flag in do_one_cmd, which exempted stub commands from range, bang,
#       count and argument checks, and can no longer be true;
#   the user-command test `(int)cmdidx < 0` -- nothing assigns a negative index;
#   the py3 and vim9 digit rules in find_ex_command -- no row starts with py or vim;
#   seven address types that only stub rows used -- argument list, buffers, loaded
#       buffers, tab pages twice, quickfix twice -- and their arms in five switches;
#   :if.  It was an ex_ni row that do_one_cmd special-cased to raise if_level, and
#       if_level is reset at the end of every do_cmdline while :if swallows the rest
#       of its line.  No command could ever run with it raised, so `ea.skip` was
#       already constantly FALSE, and its nineteen readers fold here.
#
# THE DELTA, declared.  Each removed name now gives E492 "Not an editor command"
# instead of E319 "not available in this version".  Both are errors with the same
# exit status, and the sweep cannot see the text.  Two things can see a difference,
# and both were agreed before this was written:
#   :if    was silently accepted (exit 0) and is now an error (exit 1);
#   `stub|cmd`  ran `cmd` after the stub's error, because a stub row with EX_TRLBAR
#       split its line at the bar; an unknown name takes the whole line, so `cmd`
#       no longer runs.  Probed below in both directions.
# And every removed name leaves the command sweep, which dispatches the names in
# the table: 489 rows, listed in REMOVED and required to be exactly the stub rows.
set -eu

work=${1:?usage: whim80-edit.sh <work-dir> <state-dir>}
state=${2:?usage: whim80-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# The rows to cut are the commands this phase declares in pipes/whim.delta: the
# declared delta and the cut are one list, kept in one place.
REMOVED=$(tools/whimdelta.sh --declared 80 | tr '\n' ' ')
export REMOVED

# The binary this phase is compared against, built from its input before a byte
# of it moves.  In the background: the edits below do not wait for it, but this
# part does before it exits, so the check finds $state/old whole.
cp "$f" "$state/old.c"
(cd "$state" && gcc -O0 -static -s -w -o old old.c) &
pid_old=$!

tools/st.sh edit whim80 "$f" "$state/words"

wait $pid_old

# tools/phaserun.sh sweeps next, then runs pipes/whim80-check.sh.
