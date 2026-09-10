#!/bin/sh
# Phase 0 -- reference, tools, harness.  See GOAL.md.
#
# Usage: tools/phase0.sh <work-dir>       (run from the repository root)
#
# The phase that GOAL.md describes at greatest length is the one that needs an
# agent least: the tools already exist in tools/ and the pass does not write
# them, so what is left here is configure, build, delete the asserts, build
# again, and check the harness against the previous pass's recordings.
#
# Three things this gets right that a hand-run pass got wrong at least once:
#
#   * `make -C`, never a `cd` and then `make`.  The repository root has a
#     makefile whose default target is also `vim`, so a `cd` that does not
#     stick rebuilds THAT and reports success while the tree under test is
#     untouched.  The harness self-test then reported zero differing cases for
#     a binary that had never been rebuilt.
#   * The asserts are found from the OBJECTS.  A grep over the sources matches
#     vim's own `in_assert_fails` and gets the count wrong.
#   * The self-check is against `.reference/baselines`, and it expects a
#     specific NON-ZERO answer.  The pristine binary must differ from the
#     recorded baselines in exactly the six cases Phase 1 is about to cause --
#     four from the compiled-in vimrc and two from +extra_search.  Zero would
#     mean the harness is not running; seven would mean something else moved.
set -eu

work=${1:?usage: phase0.sh <work-dir>}
src="$work/src"
jobs=$(nproc 2>/dev/null || echo 4)

# --- configure and build --------------------------------------------------
( cd "$src" && ./configure --with-features=tiny --disable-gui >/dev/null 2>&1 )
echo "  configure    tiny, no gui"

make -C "$src" -j"$jobs" >/dev/null 2>&1
echo "  build        $src/vim"

# --- the asserts, and <assert.h> with them --------------------------------
python3 tools/dropasserts.py "$work"
make -C "$src" -j"$jobs" >/dev/null 2>&1
echo "  rebuild      after the asserts"

# --- prove the harness runs, and that it disagrees in exactly the right way -
# A check that passes when the harness is broken is not a check.  This one has
# a specific expected answer, so silence is not success.
base=.reference/baselines
if [ -d "$base/behaviour" ]; then
    out=$(mktemp -d)
    python3 tools/behaviour.py "$src/vim" "$out" >/dev/null
    differ=$(diff -rq "$base/behaviour" "$out" 2>/dev/null | grep -c '^Files' || true)
    rm -rf "$out"
    if [ "$differ" = 6 ]; then
        echo "  harness      6 cases differ from the baseline, as Phase 1 owns"
    else
        echo "  harness      $differ cases differ, expected 6 -- Phase 1's own"
        echo "               deltas are ins_bs, ins_tab_et, undo_block,"
        echo "               undo_redo, match_cmd, nohlsearch.  Zero means the"
        echo "               harness is not running; more means something else"
        echo "               moved and it is not this phase's to absorb."
        exit 1
    fi
else
    echo "  harness      no $base/behaviour -- first pass, nothing to check against"
fi
