#!/bin/sh
# Pure phase 20 -- six options that no longer decide anything.  See PURE-GOAL.md.
#
# Usage: tools/pure20.sh <work-dir>      (run from the repository root)
#
# 'path' and 'suffixesadd' have been inert since the file finder went, 'tags'
# and 'tagcase' since the tag stack, 'autoread' since the timestamp poll, and
# 'swapfile' since the swap file.  All six are still here, because a row is what
# initialises its global and tools/dropoptions.py refuses to leave one dangling
# -- Phase 14's trap, which this phase finally clears rather than works around.
#
# THE ORDER IS THE PHASE, and it is forced rather than chosen:
#
#   1. the three readers that are not plumbing (tools/noinertopts.py)
#   2. the rows, with --local (tools/dropoptions.py)
#   3. SWEEP -- which is what removes did_set_tagcase() and did_set_swapfile(),
#      the option callbacks, reachable only from the rows
#   4. the buffer fields and their plumbing (tools/droplocal.py)
#   5. sweep again
#
# Steps 3 and 4 cannot swap.  The callbacks read the buffer field, so removing
# the field first stops the file compiling; the sweep works by reading gcc's
# warnings, so a file that does not compile is a file the sweep cannot act on,
# and the callbacks would stay for ever.
#
# THE DELTA: none.  All six options report E518 instead of a value that decided
# nothing.
set -eu

work=${1:?usage: pure17.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/noinertopts.py "$f"
python3 tools/dropoptions.py "$f" --local \
    path suffixesadd tags tagcase autoread swapfile


tools/sweep.sh "$f"
python3 tools/droplocal.py "$f" b_p_path b_p_sua b_p_tags b_p_tc b_p_ar b_p_swf
tools/sweep.sh "$f"

# The post-condition, and the check that was missing when this phase first ran.
# dropoptions.py --strict asks "does anything still read this global?", but it
# has to ask BEFORE the sweep, when the option's own callback still does.  After
# the sweep the question is answerable and the answer must be nothing at all --
# an unread global is itself swept, so the right count is zero mentions, not one.
for g in p_path p_sua p_tags p_tc p_ar p_swf; do
    n=$(grep -c "\b$g\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  globals      $g still has $n mentions after the sweep"
        echo "               a dropped row leaves its global uninitialised, and a"
        echo "               reader of it is a segfault before the first keystroke"
        grep -n "\b$g\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  globals      none of the six is mentioned anywhere any more"

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
