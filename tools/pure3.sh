#!/bin/sh
# Pure phase 3 -- no splash screen, no :intro, no :version.  See PURE-GOAL.md.
#
# Usage: tools/pure3.sh <work-dir>       (run from the repository root)
#
# An embedded editor starts in a buffer, not on a title card.  Three entry
# points: the two command rows, and the splash's two call sites in the redraw
# path -- that last one is why this is not simply two more rows repointed.
# maybe_intro_message() is called when the buffer is empty and no file was
# named, so an editor whose :intro is ex_ni would still greet you.
#
# THE DELTA, cumulative against slim-vim's baselines: helpclose from phase 1,
# and now intro and version.  Both of those succeed in slim-vim and report E319
# here.  Nothing else may move.
#
# --version, --help and -h/-? go too.  Their branches become the error an
# unrecognised option already produces, so nothing is left that exists only to
# refuse -- and with list_version() goes everything it printed, including
# pathdef's compiled_user and compiled_sys, which bake the BUILDING MACHINE'S
# HOSTNAME into the binary.  That is worth removing on an embedded artifact's
# account, and worth removing twice on a reproducible one.
set -eu

work=${1:?usage: pure3.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")

# --- cut the entry points -------------------------------------------------
python3 tools/nointro.py "$f"

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
tools/puredelta.sh "$work/pure-vim" "$f" helpclose intro version
