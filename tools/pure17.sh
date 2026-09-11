#!/bin/sh
# Pure phase 17 -- the editor stops re-reading a file it has already read.
# See PURE-GOAL.md.
#
# Usage: tools/pure17.sh <work-dir>      (run from the repository root)
#
# vim watches the files it holds.  check_timestamps() walks every buffer and
# stats its file -- from the main loop, from insert mode, from the Press ENTER
# prompt, and whenever the terminal regains focus -- and buf_check_timestamp()
# does the same for one buffer on entering it.  If the file moved underneath it
# prompts, and with 'autoread' it reloads.
#
# That is the editor initiating filesystem traffic on its own account.  Phase 15
# retired :checktime, which removed the COMMAND; this removes the POLLING, which
# is what actually reached the disk.  What is left is an editor that reads a
# file when told to and writes it when told to.
#
# NOT touched: check_mtime(), which buf_write() calls before overwriting a file
# that changed since it was read.  That is not polling -- it happens only when
# the user asks to write, and it is what stops a write silently clobbering
# someone else's edit.  b_mtime_read is still recorded on read, so it still
# works.
#
# 'autoread' cannot go: it is PV_BOTH, and its row is what initialises the
# global.  It stays, and now decides nothing.
#
# THE DELTA: none the harness records.  Nothing it does changes a file behind
# the editor's back, so nothing it does reaches this code.
set -eu

work=${1:?usage: pure17.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nostat.py "$f"


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
