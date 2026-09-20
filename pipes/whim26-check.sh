#!/bin/sh
# Whim phase 26, the check -- five signals, not twenty-one.
# See pipes/whim26-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim26-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim26-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim26-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim26-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

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

tools/phasecheck.sh "$work" "$f" "$state/symbols"

for g in sigaltstack sysconf; do
    if grep -qx -- "$g" .cache/symbols/last/undefined; then
        echo "  symbols      $g is still undefined in the object"
        exit 1
    fi
done
echo "  symbols      sigaltstack and sysconf are gone from nm -u"

tools/phasebuild.sh "$work" "$before_lines"

# The one that matters and no harness makes: send SIGTERM to an editor sitting
# on a pty, and require the terminal to come back cooked.  A wedged terminal is
# the failure this phase is keeping a handler FOR.
own_checks() {
    if tools/st.sh termrestore "$work/whim-vim"; then
        echo "  terminal     SIGTERM still puts the terminal back"
    else
        echo "  terminal     SIGTERM left the terminal raw -- the deathtrap is what"
        echo "               this phase kept SIGHUP and SIGTERM for"
        return 1
    fi
}
# The declared delta is not checked here: tools/phaserun.sh checks the stage's, once,
# after every check in the stage has passed.
own_checks
