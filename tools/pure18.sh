#!/bin/sh
# Pure phase 18 -- a file name means the file of that name.  See PURE-GOAL.md.
#
# Usage: tools/pure18.sh <work-dir>      (run from the repository root)
#
# 'path' searching is the last of the three ways this editor knew where files
# live, after globbing (Phase 11) and 'tags' (Phase 14).  vim_findfile() walks a
# path list downward and upward, remembers directories it has visited so a
# symlink loop cannot trap it, and can be asked for the second match and the
# third -- 866 lines behind :find, :sfind, :tabfind and gf.
#
# :find, :sfind and :tabfind are retired: the whole of what they do is the
# search.
#
# gf IS KEPT, and resolves the name literally.  It is the one place a user names
# a file from inside the buffer rather than on a command line, and taking it
# away would be taking away the naming rather than the searching.  Fifteen lines
# against eight hundred and sixty-six, and it reaches the filesystem no
# differently from :e.
#
# 'path' and 'suffixesadd' cannot go -- PV_BOTH and PV_BUF, and a row is what
# initialises its global.  They stay, and now decide nothing.
#
# THE DELTA: gf opens the name under the cursor if there is a file of that name
# rather than searching 'path' for one.  NO Ex command moves, and that is Phase
# 14's lesson again rather than a surprise: retiring a command only shows in the
# sweep if it used to SUCCEED, and :find, :sfind and :tabfind already failed for
# want of an argument.
set -eu

work=${1:?usage: pure17.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nofind.py "$f"
python3 tools/retire.py "$f" find sfind tabfind


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

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
