#!/bin/sh
# Pure phase 25 -- there is nothing to recover.  See PURE-GOAL.md.
#
# Usage: tools/pure25.sh <work-dir>      (run from the repository root)
#
# Phase 13 made the swap file memory-only: the block structure is still built,
# still paged, still where every line of the buffer lives, but it never reaches
# a disk.  What that left behind is the other half of the feature -- the code
# that reads someone else's swap file back, which is code for reading a file
# this editor cannot have written.
#
# -r and -L are the only two things that ever set `recoverymode`, so the global
# folds to FALSE and its seven readers each collapse to the branch they were
# already taking -- three of them in readfile(), which had to know whether it
# was filling a buffer from a swap file rather than from the file itself.
#
# THIS IS WHERE getpwuid GOES, the fifth of the five password-database symbols
# and the one phase 23 said would need a phase of its own: swapfile_info()
# called mch_get_uname() to say who owned a swap file.
#
# TIME IS THE PART THAT IS A DECISION.  swapfile_info() was the only caller of
# get_ctime(), leaving vim_localtime() with one user -- add_time(), the
# timestamp in :undolist and in "1 change; before #3".  It goes too, and not
# because it is unreachable: localtime_r() asks libc what the local zone is, and
# phase 24 took away every way this editor could be told.  Undo history does not
# outlive the process either (:wundo and :rundo are ex_ni), so every time
# add_time() formats is within one session and the relative form it already used
# below 100 seconds is the true one.
#
# THE DELTA: none.  :recover was pointed at ex_ni earlier and does not move --
# it already failed, needing a swap file to read.
set -eu

work=${1:?usage: pure25.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/norecover.py "$f"


tools/sweep.sh "$f"

# The post-condition, asked after the sweep.
for g in recoverymode ml_recover recover_names swapfile_info mch_get_uname \
         vim_localtime localtime_r strftime; do
    n=$(grep -cw -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  recovery     $g still has $n mentions after the sweep"
        grep -nw -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  recovery     nothing reads a swap file, and nothing asks the wall clock"

tools/canon.sh "$f"



tools/phasecheck.sh "$work" "$f" .cache/symbols/before

for g in getpwuid localtime_r strftime; do
    if grep -qx -- "$g" .cache/symbols/last/undefined; then
        echo "  symbols      $g is still undefined in the object"
        exit 1
    fi
done
echo "  symbols      getpwuid is gone -- the last of the five password symbols"

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
