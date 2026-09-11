#!/bin/sh
# Pure phase 6 -- one regexp engine, not two.  See PURE-GOAL.md.
#
# Usage: tools/pure6.sh <work-dir>       (run from the repository root)
#
# vim carries two regexp engines and an option to choose between them.  That is
# a MIGRATION PATH -- the NFA engine was new once, and 'regexpengine' existed so
# a user could go back when it misbehaved -- and an embedded fork inherits the
# machinery without inheriting the reason.
#
# This is the first removal here driven by measurement rather than by category.
# 'regexpengine' is compiled in as 1, so nothing this editor does by default
# enters the NFA code, and tools/coverage.sh never reached a line of it across
# the behaviour cases, all 600 Ex commands and the pty scenarios.  It was the
# largest single entry on that list: nfa_emit_equi_class alone is 4,122 lines.
#
# It is NOT unused -- `:set re=2` and `\%#=2` reach it -- so this is a decision,
# and the capability goes knowingly.
#
# Checked before cutting: the custom delimiter atoms this tree's upstream branch
# exists for are implemented in BOTH engines, so the backtracking one keeps them.
#
# THE DELTA: none the harness records.  It never sets 'regexpengine' and never
# writes \%#=, and every pattern it does use is compiled by the same engine as
# before -- which is the point of a default the product never changed.
set -eu

work=${1:?usage: pure3.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")

# --- cut the choice, and the option that offered it -----------------------
python3 tools/nonfa.py "$f"
python3 tools/dropoptions.py "$f" regexpengine

# The sweep cannot finish this one on its own, and that is the phase's real
# lesson.  With the entry points cut, six thousand lines of NFA engine are
# reachable from nothing -- and every function in it is MENTIONED by another
# function in it, so -Wall, which counts references, sees nothing wrong.  A
# recursive-descent parser and a mutually recursive matcher are both immune to
# reference counting by construction.
#
# tools/funcreach.py is typereach.py's argument applied to functions:
# reachability from roots, not reference counts.  It found 29 functions holding
# 4,195 lines, every one of them in the regexp_nfa.c region -- including seven
# that do not carry the prefix and would have been missed by any rule based on
# the name.
python3 tools/funcreach.py "$f" --delete

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
