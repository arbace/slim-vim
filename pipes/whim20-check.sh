#!/bin/sh
# Whim phase 20, the check -- nothing outside the process is consulted.
# See pipes/whim20-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim20-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim20-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim20-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim20-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The post-condition: after the sweep, no config path, no option and no
# environment name this phase removed is mentioned anywhere.  Asking before the
# sweep gets the wrong answer -- process_env is still there at that point and it
# is the sweep that removes it.
for g in 'getenv((char \*)((char_u \*)"HOME")' homedir init_users match_user getpwnam; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  globals      $g still has $n mentions after the sweep"
        echo "               a dropped row leaves its global uninitialised, and a"
        echo "               reader of it is a segfault before the first keystroke"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  home         nothing asks where home is, or who this is"

# The post-condition, asked AFTER the sweep for the reason above.
for g in getenv setenv unsetenv environ vim_getenv; do
    n=$(grep -cw -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  environment  $g still has $n mentions after the sweep"
        grep -nw -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  environment  nothing in the source asks the environment anything"


tools/phasecheck.sh "$work" "$f" "$state/symbols"

# And the same question of the object, which is the one that cannot be argued
# with: a libc call this source no longer writes could still arrive through a
# macro or an inline.
for g in getenv setenv unsetenv environ; do
    if grep -qx -- "$g" .cache/symbols/last/undefined; then
        echo "  symbols      $g is still undefined in the object"
        exit 1
    fi
done
echo "  symbols      getenv, setenv, unsetenv and environ are gone from nm -u"

tools/phasebuild.sh "$work" "$before_lines"
