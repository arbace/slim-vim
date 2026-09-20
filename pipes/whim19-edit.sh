#!/bin/sh
# Whim phase 19 -- the terminal is what the build says.  See WHIM-GOAL.md.
#
# Usage: pipes/whim19-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Five environment variables describe the terminal and the editor believes all
# of them: $TERM picks a capability table, $LINES and $COLUMNS override the size
# the kernel reports, $COLORS overrides the colour count the table gives, and
# $COLORFGBG is read for the background.
#
# THE COMPILED NAME IS xterm-256color, NOT xterm, and that is the whole care in
# this phase.  Measured on the shipped binary before choosing:
#
#     TERM=xterm-256color   -> term=xterm-256color  t_Co=256
#     TERM=xterm            -> term=xterm           t_Co=8
#     TERM= (unset)         -> term=xterm           t_Co=8
#
# set_termname() keeps the requested name and tests strstr(requested, "256color")
# to apply builtin_256colors on top of whichever table it chose.  So the obvious
# fallback -- the one the unset case already took -- would have cost eight of
# every nine colours the terminal can show, silently, for nothing.
# xterm-256color resolves to the same builtin_xterm table and keeps the add-on.
#
# -T <term> STAYS.  It is not the environment, and with one compiled default it
# is the only way left to say "this is a dumb terminal".  The ten built-in
# entries are still there and -T still reaches them.
#
# THE DELTA: the terminal table collapses.  Every TERM resolved to its own row
# before; now every one of them resolves to xterm-256color with 256 colours,
# because nothing consults TERM.  That is declared with --term-moved, which
# whimdelta.sh grew for this phase -- until now no phase could move that table,
# so "expected unchanged" was the whole check.
set -eu

work=${1:?usage: whim19-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh noterm "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim19-check.sh.
