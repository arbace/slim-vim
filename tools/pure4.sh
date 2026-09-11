#!/bin/sh
# Pure phase 4 -- the binary's name stops choosing what it does.  See PURE-GOAL.md.
#
# Usage: tools/pure4.sh <work-dir>       (run from the repository root)
#
# parse_command_name() reads argv[0] and picks a mode from it -- a leading `r`
# is restricted, `view` is read-only, `ex` is Ex mode.  That is a Unix
# INSTALLATION convention: you symlink rvim, view and ex at one binary and let
# the name decide.  An embedded editor is one file that was never installed and
# has no use for it.
#
# It is also the trap this repository has paid for more than once: a reference
# binary saved as `ref` runs restricted, where every shell-out fails; renaming
# the product to slim-vim needed a side-by-side check first; and every harness
# here stages the binary under test as `vim` for no reason except this function.
#
# NOTHING IS LOST, and tools/noargv0.py checks that rather than asserting it: it
# refuses to run unless -Z, -R, -y, -e and -E all still select the modes the
# name could.  Keeping the options was the requirement; proving they are still
# there is what makes the removal safe.
#
# THE DELTA: none.  The harnesses stage the binary as `vim`, which selected
# plain vim mode before and selects it now, so nothing they record can move.
set -eu

work=${1:?usage: pure3.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")

# --- cut the entry point --------------------------------------------------
python3 tools/noargv0.py "$f"

sweep=0
while :; do
    sweep=$((sweep + 1))
    was=$(sha256sum "$f" | cut -d' ' -f1)
    a=$(python3 tools/deadsweep.py "$f" | tail -1)
    c=$(python3 tools/deadprotos.py "$f" | tail -1)
    b=$(python3 tools/typereach.py "$f" --delete | tail -1)
    echo "  sweep $sweep      $a; $c; $b"
    [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$was" ] && break
    [ "$sweep" -ge 15 ] && { echo "  sweep        not converging"; exit 1; }
done

tools/canon.sh "$f"

warn=$(gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o /dev/null "$f" 2>&1 \
       | grep 'warning:' | grep -cv 'implicit-fallthrough' || true)
if [ "$warn" != 0 ]; then
    echo "  warnings     $warn besides the fall-throughs -- the sweep is not finished"
    gcc -c -O0 -Wall -Wextra -Wno-unused-parameter -o /dev/null "$f" 2>&1 \
        | grep 'warning:' | grep -v 'implicit-fallthrough' | head -5 | sed 's/^/               /'
    exit 1
fi

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" helpclose intro version
