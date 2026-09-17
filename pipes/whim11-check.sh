#!/bin/sh
# Whim phase 11, the check -- nothing is written that was not asked for.
# See pipes/whim11-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim11-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim11-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim11-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim11-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# The check this phase exists for, and the one no build can make: editing a
# file must leave NOTHING beside it.
sw=$(cd "$work" && rm -rf .swtest && mkdir .swtest && cd .swtest \
     && printf 'a\nb\n' > f.txt \
     && ../whim-vim -u NONE -i NONE -e -s -c 'normal ohello' -c 'wq' f.txt \
            </dev/null >/dev/null 2>&1
     ls -A | tr '\n' ' ')
rm -rf "$work/.swtest"
if [ "$sw" != "f.txt " ]; then
    echo "  swapfile     editing left: $sw"
    echo "               expected f.txt alone -- something still writes beside the file"
    exit 1
fi
echo "  swapfile     editing a file leaves the file, and nothing else"

# --- the delta, cumulative --------------------------------------------------
# Three surprises in this list, all of them the harness being more exact than
# the author.  :mksession and :mkview do NOT move -- they already failed.  And
# :recover leaves the list it joined in Phase 7: globbing's removal had made it
# fail differently from the slim baseline, and ex_ni makes it fail the SAME way
# again, so it stops being a difference.  A cumulative delta can shrink.
tools/whimdelta.sh "$work/whim-vim" "$f" --cases filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
