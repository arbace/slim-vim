#!/bin/sh
# Delete what the cut left unreachable, to a fixpoint -- all six kinds.
#
# Usage: tools/sweep.sh <file.c>
#
# Six tools, run in turn until a whole round changes nothing.  deadsweep.py
# asks gcc what it warned about; deadprotos.py, typereach.py, funcreach.py,
# deadfields.py and deadenums.py read the text.  Each feeds the others --
# deleting a function orphans a type, deleting a type orphans a prototype,
# deleting a field orphans an enumerator -- so none of them is finished until
# all of them are.
#
#   functions     deadsweep.py (gcc) and funcreach.py -- reachability, so an
#                 island that only calls itself dies too
#   prototypes    deadprotos.py
#   types         typereach.py -- reachability, same argument
#   variables     deadsweep.py, via -Wunused-variable
#   struct fields deadfields.py -- A FIELD IS NOT A VARIABLE, so no warning
#                 names one nothing reads.  It refuses while ml_recover() can
#                 still read a swap file, because until then a struct layout is
#                 a disk format.
#   enumerators   deadenums.py -- gcc has no warning either, and deleting one
#                 renumbers the ones after it, so survivors are pinned to their
#                 DWARF values (tools/enumvals.sh), dumped on first need and
#                 compared again once the sweep is done.
#
# THIS USED TO BE FOUR KINDS, and the other two were a phase of their own that
# ran twice -- once part way through the pipeline and once at the tip -- because
# every phase after the first run deleted code that orphaned more fields and
# enumerators and nothing in its own sweep would notice.  An invariant that holds
# only where it is asserted is not one.  Every sweep asserts it now, so every
# boundary satisfies it.
#
# Every phase ran its own copy of this loop, character for character, and the
# copies had begun to drift: the later ones had funcreach.py in the round and
# the earlier ones did not.  One file, called from all of them.
#
# MEASURED AND REJECTED: running the three textual tools to their own inner
# fixpoint before asking gcc again.  gcc costs seven seconds and the three
# together cost one, so the shape looks obviously right -- fewer expensive
# rounds bought with cheap ones.  It made the whim pass 47 seconds SLOWER
# (1,364s against 1,317s), because proving the cheap tools have stopped costs a
# whole extra pass of them in every round, and they cascade less often than the
# argument assumes.  The obvious shape was worth measuring and not worth
# keeping.
#
# THE LAST ROUND'S COMPILES ARE KEPT, in .cache/compile, because the round that
# ends a sweep is by definition a round on a file that then does not change --
# and phasecheck.sh wanted exactly those, for exactly the same two answers: the
# warnings deadsweep.py asked for, and an object to run `nm` over, which is the
# plain one the build rides along on (below).  It reuses them when both shas
# still match, saving one compile of a 145,000-line file in every phase.
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

# The enumerator values of THIS input, kept for the whole sweep so that every
# round pins to the original numbering.  deadenums.py writes it the first time
# something is dead, and not before -- most sweeps never pay for the -g build.
vals=$(mktemp -u)

# THE BUILD RIDES ALONG.  A phase ends by building its binary, which used to be
# a second full compile of the text this loop's last round had just compiled.
# That compile cannot be reused -- -Wall -Wextra move the code, 64 bytes of
# .text -- so each round also compiles a PLAIN object of the text it starts
# from, in the background, on a core that was idle anyway.  The round that
# changes nothing started from the final text, so its object is the one
# tools/phasebuild.sh links: byte-identical to `make`, in a twentieth of a second.
# A round that does change the file makes its object stale, and the next round's
# replaces it.
mkdir -p .cache/compile
spec_pid=
spec() {
    if [ -n "$spec_pid" ]; then kill "$spec_pid" 2>/dev/null || true; wait "$spec_pid" 2>/dev/null || true; fi
    rm -f .cache/compile/spec.*
    cp "$f" ".cache/compile/spec.$round.c"
    sha256sum "$f" | cut -d' ' -f1 > ".cache/compile/spec.$round.sha"
    gcc -c -O0 -o ".cache/compile/spec.$round.o" ".cache/compile/spec.$round.c" 2>/dev/null &
    spec_pid=$!
}
trap 'rm -f "$vals"; [ -n "$spec_pid" ] && kill "$spec_pid" 2>/dev/null; rm -f .cache/compile/spec.*' EXIT
rm -f .cache/compile/build.o .cache/compile/build.sha

# A TOOL IS NOT RUN AGAIN ON TEXT IT HAS ALREADY PASSED.  Every tool here is a
# function of the file's bytes -- deadenums.py's values file too, which is
# written once, on first need, and never changes after -- so a
# tool that ran and changed nothing on exactly these bytes would change nothing
# again.  The commonest round is one where deadsweep.py deletes something and
# the other six had nothing to do: the next round's deadsweep sees new text, and
# the six after it see the text they just passed.  Each tool remembers the
# sha256 it last passed, and forgets it the moment it changes the file.
#
# The fixpoint is untouched: a round that changes nothing is still a round in
# which every tool either ran on the final text or had already passed it, byte
# for byte.  deadsweep.py does not skip in practice -- it runs first, and a round
# only follows one that changed the file -- so its warnings in .cache/compile
# are of the final text; were it ever to skip, their sha would be stale and
# phasecheck.sh would compile for itself.
#
# SIMULATED AND NOT TAKEN: treating canon.sh's changes as invisible to the other
# six, on the argument that canon moves layout and they read tokens.  It does
# not only move layout -- brace.py adds braces, onedecl.py splits declarators,
# forcomma.py hoists comma expressions -- and the five textual tools read lines,
# so a file canon has reshaped is one they have not seen.  A sweep that ended on
# that argument would end on a text some tool never ran on.
pass() {
    name=$1
    shift
    now=$(sha256sum "$f" | cut -d' ' -f1)
    eval "seen=\${passed_$name:-}"
    if [ "$now" = "$seen" ]; then
        said=$(printf '  %-12s passed this text already' "$name")
        return 0
    fi
    said=$("$@" | tail -1)
    if [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$now" ]; then
        eval "passed_$name=$now"
    else
        eval "passed_$name="
    fi
}

round=0
while :; do
    round=$((round + 1))
    was=$(sha256sum "$f" | cut -d' ' -f1)
    spec
    pass deadsweep python3 tools/deadsweep.py "$f" --keep .cache/compile; a=$said
    pass deadprotos python3 tools/deadprotos.py "$f"; c=$said
    pass typereach python3 tools/typereach.py "$f" --delete; b=$said
    pass funcreach python3 tools/funcreach.py "$f" --delete; d=$said
    pass deadfields python3 tools/deadfields.py "$f" --delete; g=$said
    pass deadenums python3 tools/deadenums.py "$f" "$vals" --delete; h=$said
    pass canon tools/canon.sh "$f" --once; e=$said
    echo "  sweep $round      $a; $c; $b; $d; $g; $h;   $e"
    [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$was" ] && break
    [ "$round" -ge 15 ] && { echo "  sweep        not converging"; exit 1; }
done

# Only if an enumerator was dumped for, which is only if one was dead.
if [ -f "$vals" ]; then
    python3 tools/deadenums.py "$f" "$vals" --verify
fi

# The last round started from the final text, so its object is the build's --
# once it has finished, and only if it compiled.
if wait "$spec_pid" && [ "$(cat ".cache/compile/spec.$round.sha")" = "$(sha256sum "$f" | cut -d' ' -f1)" ]; then
    mv ".cache/compile/spec.$round.o" .cache/compile/build.o
    mv ".cache/compile/spec.$round.sha" .cache/compile/build.sha
fi
spec_pid=
