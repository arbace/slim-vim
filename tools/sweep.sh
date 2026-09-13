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
#
# THE LAST ROUND'S COMPILE IS KEPT, in .cache/compile, because the round that
# ends a sweep is by definition a compile of a file that then does not change --
# and phasecheck.sh wanted exactly that compile, for exactly the same two
# answers.  It reuses it when the sha still matches, saving one compile of a
# 145,000-line file in every phase.
#
# THAT IS WHY canon.sh RUNS IN THE ROUND and not after the loop.  It was after
# the loop, and the obvious move -- run it before instead, so the terminating
# compile sees the final text -- was measured to commute on one phase and then
# moved 27 of 32 boundaries when the whole pass ran.  Of course it did: the
# sweep DELETES, and a deletion leaves a run of blank lines that only canon
# takes out, so a file canonicalised before a sweep is not canonical after one.
# The product came out byte-identical, because each later phase's canon cleaned
# up what the one before left -- which is exactly the kind of accident that
# makes an invariant stop being one.
#
# Running it at the END OF EACH ROUND gives both: every round leaves the file
# canonical, so the round that changes nothing is a round whose compile saw the
# final text.  It runs --once, because THIS loop is the fixpoint: if canon
# changed something the round changed something and we go round again, so
# proving canon has settled on its own would prove it twice.
set -eu

f=${1:?usage: sweep.sh <file.c>}

round=0
while :; do
    round=$((round + 1))
    was=$(sha256sum "$f" | cut -d' ' -f1)
    a=$(python3 tools/deadsweep.py "$f" --keep .cache/compile | tail -1)
    c=$(python3 tools/deadprotos.py "$f" | tail -1)
    b=$(python3 tools/typereach.py "$f" --delete | tail -1)
    d=$(python3 tools/funcreach.py "$f" --delete | tail -1)
    e=$(tools/canon.sh "$f" --once)
    echo "  sweep $round      $a; $c; $b; $d;   $e"
    [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$was" ] && break
    [ "$round" -ge 15 ] && { echo "  sweep        not converging"; exit 1; }
done
