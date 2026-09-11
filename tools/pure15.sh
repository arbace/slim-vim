#!/bin/sh
# Pure phase 15 -- nothing is written that was not asked for.  See PURE-GOAL.md.
#
# Usage: tools/pure15.sh <work-dir>      (run from the repository root)
#
# A swap file is not a recovery add-on bolted to the side of the editor; it is
# MEMLINE'S BACKING STORE, created beside every file you open, written to as you
# type, deleted on a clean exit.  For an embedded editor it is the last thing
# writing a file nobody asked for, and it is why 'directory' is searched for a
# free .swp name and why a 576-line recovery reader exists.
#
# What goes is the FILE, not the memline.  mf_open() already supports a memfile
# with no name -- that is what `:set noswapfile` has always produced -- so the
# buffer keeps its block structure and never acquires a fd.  The cost is real
# and was agreed before this was written: NO CRASH RECOVERY, and a buffer larger
# than memory can no longer page out to disk.
#
# With it go the two other things that write without being asked: :mkvimrc,
# :mkexrc, :mksession and :mkview, which drop a script into the current
# directory, and :checktime, which stats a file behind the user's back.
#
# NOT done here, and worth saying: the AUTOMATIC timestamp check remains.
# check_timestamps() is still called from main_loop(), edit() and wait_return(),
# so the editor still notices a file changing underneath it -- retiring
# :checktime removes the command, not the polling.  That is a separate cut with
# a separate delta.
#
# THE DELTA: eight command names report that they are not available.
# 'directory', 'updatecount' and 'swapsync' stop existing.  'swapfile' cannot
# go -- it is PV_BUF and its row is what initialises the global -- so it stays
# and is now always effectively off.
set -eu

work=${1:?usage: pure15.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/noswap.py "$f"
python3 tools/retire.py "$f" recover preserve swapname \
    mkvimrc mkexrc mksession mkview checktime
python3 tools/dropoptions.py "$f" directory updatecount swapsync

tools/sweep.sh "$f"

tools/canon.sh "$f"


tools/phasecheck.sh "$work" "$f" .cache/symbols/before

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# The check this phase exists for, and the one no build can make: editing a
# file must leave NOTHING beside it.
sw=$(cd "$work" && rm -rf .swtest && mkdir .swtest && cd .swtest \
     && printf 'a\nb\n' > f.txt \
     && ../pure-vim -u NONE -i NONE -e -s -c 'normal ohello' -c 'wq' f.txt \
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
# :recover leaves the list it joined in Phase 11: globbing's removal had made it
# fail differently from the slim baseline, and ex_ni makes it fail the SAME way
# again, so it stops being a difference.  A cumulative delta can shrink.
tools/puredelta.sh "$work/pure-vim" "$f" --cases filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
