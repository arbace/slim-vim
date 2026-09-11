#!/bin/sh
# Delete what the cut left unreachable, to a fixpoint.
#
# Usage: tools/sweep.sh <file.c>
#
# Four tools, run in turn until a whole round changes nothing.  deadsweep.py
# asks gcc what it warned about; deadprotos.py, typereach.py and funcreach.py
# read the text.  Each feeds the others -- deleting a function orphans a type,
# deleting a type orphans a prototype -- so none of them is finished until all
# of them are.
#
# Every phase ran its own copy of this loop, character for character, and the
# copies had begun to drift: the later ones had funcreach.py in the round and
# the earlier ones did not.  One file, called from all of them.
#
# MEASURED AND REJECTED: running the three textual tools to their own inner
# fixpoint before asking gcc again.  gcc costs seven seconds and the three
# together cost one, so the shape looks obviously right -- fewer expensive
# rounds bought with cheap ones.  It made the pure pass 47 seconds SLOWER
# (1,364s against 1,317s), because proving the cheap tools have stopped costs a
# whole extra pass of them in every round, and they cascade less often than the
# argument assumes.  The obvious shape was worth measuring and not worth
# keeping.
set -eu

f=${1:?usage: sweep.sh <file.c>}

round=0
while :; do
    round=$((round + 1))
    was=$(sha256sum "$f" | cut -d' ' -f1)
    a=$(python3 tools/deadsweep.py "$f" | tail -1)
    c=$(python3 tools/deadprotos.py "$f" | tail -1)
    b=$(python3 tools/typereach.py "$f" --delete | tail -1)
    d=$(python3 tools/funcreach.py "$f" --delete | tail -1)
    echo "  sweep $round      $a; $c; $b; $d"
    [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$was" ] && break
    [ "$round" -ge 15 ] && { echo "  sweep        not converging"; exit 1; }
done
