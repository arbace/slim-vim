#!/bin/sh
# Pure phase 29 -- five signals, not twenty-one.  See PURE-GOAL.md.
#
# Usage: tools/pure29.sh <work-dir>      (run from the repository root)
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
#   SIGTERM    files -- it cannot, phase 23 emptied ml_sync_all() and phase 26
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

work=${1:?usage: pure29.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nosignals.py "$f"


tools/sweep.sh "$f"

# The post-condition: exactly eight signals are named, and each is one of the
# five kept or one of the three the suspend dance uses.
named=$(grep -o '\bSIG[A-Z0-9]*\b' "$f" | sort -u | tr '\n' ' ')
if [ "$named" != "SIGALRM SIGCONT SIGHUP SIGINT SIGPIPE SIGTERM SIGTSTP SIGWINCH " ]; then
    echo "  signals      the file names: $named"
    echo "               expected the five kept, plus SIGCONT/SIGALRM/SIGPIPE,"
    echo "               which mch_suspend() sets around the stop"
    exit 1
fi
for g in sigaltstack may_core_dump catch_sigpwr catch_sigusr1 got_sigusr1 \
         signal_stack sigstk; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  signals      $g still has $n mentions after the sweep"
        exit 1
    fi
done
echo "  signals      $(grep -c '{SIG' "$f") in the table; resize, interrupt,"
echo "               suspend, and a terminal put back on the way out"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

for g in sigaltstack sysconf; do
    if grep -qx -- "$g" .cache/symbols/last/undefined; then
        echo "  symbols      $g is still undefined in the object"
        exit 1
    fi
done
echo "  symbols      sigaltstack and sysconf are gone from nm -u"

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# The one that matters and no harness makes: send SIGTERM to an editor sitting
# on a pty, and require the terminal to come back cooked.  A wedged terminal is
# the failure this phase is keeping a handler FOR.
if python3 tools/termrestore.py "$work/pure-vim"; then
    echo "  terminal     SIGTERM still puts the terminal back"
else
    echo "  terminal     SIGTERM left the terminal raw -- the deathtrap is what"
    echo "               this phase kept SIGHUP and SIGTERM for"
    exit 1
fi

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
