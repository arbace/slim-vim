#!/bin/sh
# Nothing in the file is unreachable.  Shared by whim phases 28 and 37.
#
# Usage: tools/unreachable.sh <work-dir> <delta-word>...
#
# ONE IMPLEMENTATION, CALLED TWICE, and the reason is that the invariant must
# not be able to drift between the two places it is asserted.
#
# Every phase sweeps what its own cut orphaned; this asks the whole file a
# question none of them can: IS ANYTHING LEFT THAT NOTHING REACHES?  The sweep
# covers four of the six kinds --
#
#   functions     deadsweep.py (gcc) and funcreach.py -- reachability, so an
#                 island that only calls itself dies too
#   prototypes    deadprotos.py
#   types         typereach.py -- reachability, same argument
#   variables     deadsweep.py, via -Wunused-variable
#
# -- AND TWO ARE COVERED BY NOTHING AT ALL:
#
#   enumerators   gcc has no warning, typereach counts them only to decide
#                 whether their enum is alive.
#   struct fields A FIELD IS NOT A VARIABLE: no warning names one that nothing
#                 reads and the sweep cannot see it.
#
# Those two are why this runs twice.  Phase 28 clears the backlog; every phase
# after it deletes code that can orphan more, and nothing in a phase's own sweep
# would notice.  Measured after phase 36, with only phase 28 asserting: 42 dead
# struct fields and 12 dead enumerators had accumulated, none of them reachable
# and none of them reported by anything.  So the assertion is pinned to the tip
# as well, which is what makes it an invariant rather than a one-off cleanup.
#
# THE ENUMERATOR TRAP: an enumerator's value is its position, so deleting one
# renumbers every implicit one after it, and several enums here index a parallel
# table.  The values are read from DWARF before and after -- the compiler has
# already done the arithmetic -- the first survivor after each deleted run is
# pinned to the value it had, and every surviving name must come back with the
# value it went in with.  That is stronger than the build, which compiles a
# silently renumbered table without complaint.
#
# THE DELTA: none of its own.  Nothing removed here was reachable, so nothing
# that ran before can stop running; the words passed in are the cumulative delta
# of the phases before it.
set -eu

work=${1:?usage: unreachable.sh <work-dir> <delta-word>...}
shift
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- what the compiler knows, before ---------------------------------------
vals=$(mktemp -u)
sh tools/enumvals.sh "$f" "$vals.before"

# --- cut what nothing reaches, TO A FIXPOINT --------------------------------
# One pass is not enough, and the assertion below is what proved it: removing a
# field or an enumerator orphans a type, removing the type orphans more, and
# the first run of this came out of one pass with three enumerators still dead.
# Same argument as the sweep's own loop, one level up -- and the values passed
# to deadenums stay the ORIGINAL ones every round, because it is the original
# numbering that has to survive.
round=0
while :; do
    round=$((round + 1))
    was=$(sha256sum "$f" | cut -d' ' -f1)
    python3 tools/deadfields.py "$f" --delete || true
    python3 tools/deadenums.py "$f" "$vals.before" --delete || true
    tools/sweep.sh "$f"
    [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$was" ] && break
    if [ "$round" -ge 8 ]; then
        echo "  unreachable  not converging after $round rounds"
        exit 1
    fi
done
echo "  unreachable  fixpoint after $round round$([ "$round" = 1 ] || echo s)"

# --- and now the assertion, which is the point -----------------------------
fail=0
python3 tools/deadfields.py "$f" || fail=1
python3 tools/deadenums.py "$f" "$vals.before" || fail=1
n=$(python3 tools/typereach.py "$f" | sed 's/.*, \([0-9]*\) unreachable/\1/')
[ "$n" = 0 ] || { echo "  unreachable  $n type definitions"; fail=1; }
n=$(python3 tools/funcreach.py "$f" | sed 's/.*reachable, \([0-9]*\) not.*/\1/')
[ "$n" = 0 ] || { echo "  unreachable  $n functions"; fail=1; }
n=$(python3 tools/deadprotos.py "$f" | grep -c 'never called:' || true)
[ "$n" = 0 ] || { echo "  unreachable  prototypes remain"; fail=1; }
if [ "$fail" != 0 ]; then
    echo "  unreachable  the file still holds something nothing reaches"
    exit 1
fi
echo "  unreachable  nothing: no function, type, prototype, variable,"
echo "               enumerator or struct field that nothing reaches"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/whim-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# --- and that no surviving enumerator moved --------------------------------
sh tools/enumvals.sh "$f" "$vals.after"
moved=$(join -t= -j1 <(sort "$vals.before") <(sort "$vals.after") 2>/dev/null |
        awk -F= '$2 != $3' | wc -l)
gone=$(comm -23 <(cut -d= -f1 "$vals.before" | sort) \
                <(cut -d= -f1 "$vals.after" | sort) | wc -l)
rm -f "$vals.before" "$vals.after"
if [ "$moved" != 0 ]; then
    echo "  enumvals     $moved surviving enumerators changed value"
    exit 1
fi
echo "  enumvals     $gone enumerators gone, and not one survivor moved"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd "$@"
