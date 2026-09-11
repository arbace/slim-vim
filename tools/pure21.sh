#!/bin/sh
# Pure phase 21 -- the last two per-buffer encoding options.  See PURE-GOAL.md.
#
# Usage: tools/pure21.sh <work-dir>      (run from the repository root)
#
# 'fileencoding' names the encoding a buffer was read in and will be written
# back in, and 'bomb' whether it had a byte-order mark.  With one encoding and no
# BOM, both have had one possible value since Phase 16 -- but unlike the six
# Phase 20 took, these are not plumbing: eight functions read them, and each had
# to be looked at.  buf_write() and readfile() take the buffer's encoding as a
# conversion target; bomb_size() reports how many bytes of the file are a BOM
# for the g CTRL-G count; save_file_ff() and file_ff_differs() remember the pair
# so :w can warn that they changed; g8 converts to the buffer's encoding to find
# a byte illegal in it; and add_b0_fenc() writes the name into a swap file's
# block zero, of which there have been none since Phase 15.
#
# What the options leave behind once nothing compares them is a pair of
# REMEMBERED COPIES in buf_T, written on every read and looked at by nobody.  A
# struct field is not a variable, so no warning reports it and the sweep cannot
# see it -- which is why those are listed in the tool rather than swept.
#
# 'fileformat', 'endofline' and 'endoffile' can still change under a buffer, so
# file_ff_differs() keeps those and loses only the two that cannot.
#
# THE DELTA: none.  Both options report E518 instead of a value with one
# possible setting, and what is left is 'encoding', alone, reporting utf-8.
set -eu

work=${1:?usage: pure17.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nofenc.py "$f"
python3 tools/dropoptions.py "$f" --local fileencoding bomb


tools/sweep.sh "$f"
python3 tools/droplocal.py "$f" b_p_fenc b_p_bomb
tools/sweep.sh "$f"

# The post-condition, and the check that was missing when this phase first ran.
# dropoptions.py --strict asks "does anything still read this global?", but it
# has to ask BEFORE the sweep, when the option's own callback still does.  After
# the sweep the question is answerable and the answer must be nothing at all --
# an unread global is itself swept, so the right count is zero mentions, not one.
# The names as well as the globals.  set_string_option_direct((char_u *)"fenc")
# resolves an option through findoption(), which answers -1 for a row that is
# not there, and the caller does not check -- silent Ex mode then exits 1
# without printing, and every recorded exit status in the harness moves at once.
# That is what this phase did on its first run, and what Phase 19 did with
# "fencs".  dropoptions.py's name guard is --strict, and --local skips it.
for g in p_fenc p_bomb b_start_fenc b_start_bomb '"fenc"' '"bomb"'; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  globals      $g still has $n mentions after the sweep"
        echo "               a dropped row leaves its global uninitialised, and a"
        echo "               reader of it is a segfault before the first keystroke"
        grep -n -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  globals      neither option is named or read anywhere any more"

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
