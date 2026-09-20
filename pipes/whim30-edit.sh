#!/bin/sh
# Whim phase 30 -- K and the tag jumps, keeping * and #.  See WHIM-GOAL.md.
#
# Usage: pipes/whim30-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# nv_ident() is not one command, it is five, and they have nothing in common but
# the first step -- read the identifier under the cursor:
#
#     *  #  g*  g#      search for that word          -- STAY
#     K                 run 'keywordprg' on it        -- goes
#     ]  CTRL-]  g]     jump to its tag               -- goes
#
# * and # are among the most used keys in vim and are pure search, so this phase
# rewrites the function rather than deleting it.  K runs 'keywordprg' through a
# shell and phase 6 took the shell; the tag jumps build `ta `, `tj `, `ts ` or
# `he! ` and hand them to do_cmdline_cmd(), and phase 10 made every one of those
# ex_ni.  Both arms have been building commands that fail.
#
# THE DELTA: none.  These are normal-mode keys, so no Ex command moves, and no
# behaviour case presses any of them.  The phase checks the halves itself.
set -eu

work=${1:?usage: whim30-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh noident "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim30-check.sh.
