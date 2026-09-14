#!/bin/sh
# Whim phase 14 -- a file name means the file of that name.  See WHIM-GOAL.md.
#
# Usage: tools/whim14.sh <work-dir>      (run from the repository root)
#
# 'path' searching is the last of the three ways this editor knew where files
# live, after globbing (Phase 7) and 'tags' (Phase 10).  vim_findfile() walks a
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

work=${1:?usage: whim14.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nofind.py "$f"
python3 tools/retire.py "$f" find sfind tabfind


tools/sweep.sh "$f"


tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
