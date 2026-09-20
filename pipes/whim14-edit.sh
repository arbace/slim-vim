#!/bin/sh
# Whim phase 14 -- a file name means the file of that name.  See WHIM-GOAL.md.
#
# Usage: pipes/whim14-edit.sh <work-dir> <state-dir>      (run from the repository root)
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

work=${1:?usage: whim14-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh nofind "$f"
tools/st.sh retire "$f" find sfind tabfind

# tools/phaserun.sh sweeps next, then runs pipes/whim14-check.sh.
