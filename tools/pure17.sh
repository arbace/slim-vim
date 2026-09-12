#!/bin/sh
# Pure phase 7 -- the last two encoding options.  See PURE-GOAL.md.
#
# Usage: tools/pure17.sh <work-dir>      (run from the repository root)
#
# Phase 8 emptied 'fileencodings' and said so.  It was true at startup and not
# afterwards: set_option_default() special-cases the option, so `:set fencs&`
# restored ucs-bom,utf-8,default,latin1 from fencs_utf8_default -- a third
# reference that phase did not find, because it names the STRING rather than the
# function the other two called.  Measured on the shipped binary: fileencodings=
# at startup, fileencodings=ucs-bom,utf-8,default,latin1 after a reset.
#
# Three readers go, and with them the two options can finally follow:
# set_option_default() stops special-casing 'fileencodings', which is what makes
# Phase 8's claim true at every moment rather than one; readfile() stops
# choosing between an empty list and a list to walk, and takes the buffer's own
# 'fileencoding', which is the branch the empty case already took; and
# did_set_encoding() stops setting up a conversion between 'termencoding' and
# 'encoding', which convert_setup() has answered CONV_NONE to since Phase 8.
#
# 'encoding' STILL cannot go, and this is where that stops being temporary:
# p_enc is the NAME of the one encoding, compared against in twenty-nine places.
# Removing the option would mean removing the name, and the name does work.
#
# THE DELTA: none.  `:set fencs&` no longer restores a list of encodings this
# build cannot convert between, which is a correction rather than a change.
set -eu

work=${1:?usage: pure17.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nofencs.py "$f"


tools/sweep.sh "$f"
python3 tools/dropoptions.py "$f" --strict fileencodings termencoding
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
