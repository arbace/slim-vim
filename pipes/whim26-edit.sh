#!/bin/sh
# Whim phase 26 -- five signals, not twenty-one.  See WHIM-GOAL.md.
#
# Usage: pipes/whim26-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# signal_info[] has twenty-one entries and five handlers.  Reviewed one at a
# time, four earn their keep:
#
#   SIGWINCH   sig_winch() sets do_resize, read in nine places.  Without it the
#              editor never learns the terminal changed size.
#   SIGINT     catch_sigint() sets got_int, READ IN 222 PLACES -- which is the
#              argument.  got_int is how every long operation is interruptible;
#              without the handler CTRL-C reverts to its default action, which
#              kills the process and loses the buffer.
#   SIGTSTP    CTRL-Z and :suspend, and the only caller of raise().
#   SIGHUP     reaching deathtrap(), whose remaining job is not preserving
#   SIGTERM    files -- it cannot, phase 21 emptied ml_sync_all() and phase 24
#              removed preserve_exit()'s loop -- but prepare_to_exit(), which
#              runs settmode(TMODE_COOK) and stoptermcap().  A killed editor
#              PUTS THE TERMINAL BACK.  Without it the shell is left raw with no
#              echo and the user types `reset` blind.
#
# THE COST, decided deliberately: a crash no longer restores the terminal.
# SIGSEGV and SIGBUS take their default action.  The alternative is keeping a
# handler for conditions this editor should not have, to tidy up after a bug
# that should not exist.
#
# What goes with them: SIGPWR, whose handler called ml_sync_all() -- an empty
# function; SIGUSR1, whose flag NOTHING READS (assigned and never examined, so
# -Wunused-variable never fires and the sweep would never find it); thirteen
# more table entries; sigaltstack and its stack, which existed so a SEGV from
# stack overflow could still run a handler; and may_core_dump(), which re-raises
# to produce a core there is nobody to read.
#
# THE DELTA: none the harness records.  The Ex sweep records :suspend and :stop
# as SKIPPED -- they hand over the terminal -- and SIGTSTP stays regardless.
set -eu

work=${1:?usage: whim26-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh nosignals "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim26-check.sh.
