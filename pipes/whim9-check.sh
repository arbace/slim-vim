#!/bin/sh
# Whim phase 9, the check -- the editor stops asking the environment what language it is in.
# See pipes/whim9-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim9-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim9-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim9-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim9-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The check this phase would be sunk without: an editor that quietly became
# latin1 passes every build and linkage test there is.
tools/phasebuild.sh "$work" "$before_lines"
enc=$( cd "$work" && printf 'x\n' > .enc.txt \
       && ./whim-vim -u NONE -i NONE -e -s -c 'redir! > .enc.out' \
              -c 'set encoding?' -c 'redir END' -c 'qall!' .enc.txt \
              </dev/null >/dev/null 2>&1
       tr -d ' \n' < .enc.out; rm -f .enc.txt .enc.out )
if [ "$enc" != "encoding=utf-8" ]; then
    echo "  encoding     got '$enc', expected encoding=utf-8"
    echo "               the locale used to supply this; the default must now carry it"
    exit 1
fi
echo "  encoding     utf-8 by compiled default, with no locale asked"
