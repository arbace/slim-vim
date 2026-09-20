#!/bin/sh
# The two vendoring checks -- muslctype and muslcase -- Go against Python, over
# the corpus, both arms counted.
#
# Usage: sh tools/gocmp/vendorcmp.sh [muslctype|muslcase]...   (default both)
#
# THE TWO ARMS ARE COUNTED SEPARATELY AND THE RUN REFUSES WITHOUT BOTH.  These
# tools answer on very few inputs and decline on most, for reasons that are
# facts about the pipeline rather than about the port:
#
#   muslctype  the vendored block exists only from zero phase 15, and from
#              phase 23 it spells its sizes `usize`, which the driver's own
#              <stddef.h> does not define -- so the final zero-vim.c refuses,
#              correctly, and so does the Python.
#   muslcase   musl_toUpper[]/musl_toLower[] exist from phase 15 and are GONE
#              from phase 29, which merged them with vim's own tables into one.
#
# A comparison counting those agreements as passes would report agreement over
# hundreds of inputs having done the real work on none of them.  That is the
# defect tools/gocmp/CUTTERS.md found in ten cutters at once, and it is why
# `ok` -- both implementations did the work and agreed on every number -- is
# counted apart from `refused`, and why zero of the first fails this script.
#
# A REFUSAL IS COMPARED ON ITS FIRST LINE ONLY.  gcc names its own temporary
# directory in an error, so two failing runs can never match textually; what is
# required of them is the property that matters, that both decline and say the
# same thing about why.
set -eu

[ -d tools ] && [ -d pipes ] || { echo "vendorcmp: run me from the repository root" >&2; exit 1; }
bin=$PWD/$(sh tools/gobuild.sh)
corpus=${GOCMP_CORPUS:-.gocorpus}
tools=${*:-muslctype muslcase}
rc=0

for tool in $tools; do
    ok=0; refused=0; differ=0
    for f in "$corpus"/*/*.c; do
        [ -f "$f" ] || continue
        # `pa=$(cmd); prc=$?` IS WRONG UNDER set -e: the assignment IS the
        # failing command, so the shell exits before $? can be read -- measured,
        # the first version of this exited 1 having written nothing at all.  A
        # script whose whole job is comparing two refusals cannot use a form
        # that dies on one.
        pa=$(python3 "tools/$tool.py" --verify "$f" 2>&1) && prc=0 || prc=$?
        ga=$("$bin" "$tool" --verify "$f" 2>&1) && grc=0 || grc=$?
        if [ "$prc" != "$grc" ]; then
            differ=$((differ + 1)); echo "DIFFER status $tool $f: python=$prc go=$grc"; continue
        fi
        if [ "$prc" = 0 ]; then
            if [ "$pa" = "$ga" ]; then ok=$((ok + 1))
            else differ=$((differ + 1)); echo "DIFFER output $tool $f"; echo "  py: $pa"; echo "  go: $ga"; fi
        else
            if [ "$(printf '%s' "$pa" | head -1)" = "$(printf '%s' "$ga" | head -1)" ]; then refused=$((refused + 1))
            else differ=$((differ + 1)); echo "DIFFER refusal $tool $f"
                 echo "  py: $(printf '%s' "$pa" | head -1)"; echo "  go: $(printf '%s' "$ga" | head -1)"; fi
        fi
    done
    echo "vendorcmp $tool: $ok did the work and agreed, $refused agreed on a refusal, $differ differ"
    [ "$differ" -eq 0 ] || rc=1
    [ "$ok" -gt 0 ] || { echo "vendorcmp $tool: did the work on no input at all - vacuous" >&2; rc=1; }
done

# muslcase --generate is the strongest comparison either tool has: it derives
# the whole table from libc and writes it out, so a byte comparison covers the
# libc query, the greedy compression and the emit format at once.
case " $tools " in *" muslcase "*)
    t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
    python3 tools/muslcase.py --generate > "$t/py" 2>&1 || true
    "$bin" muslcase --generate > "$t/go" 2>&1 || true
    if cmp -s "$t/py" "$t/go"; then
        echo "vendorcmp muslcase --generate: byte-identical, $(grep -c '' "$t/py") lines"
    else
        echo "vendorcmp muslcase --generate: DIFFER"; diff "$t/py" "$t/go" | head -10; rc=1
    fi
    ;;
esac

exit "$rc"
