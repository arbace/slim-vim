#!/bin/sh
# Run every canonicaliser to a joint fixpoint.
#
# Usage: tools/canon.sh <file>        (paths are relative to the repository root)
#
# The seven passes are not independent, and running each once is not enough --
# which is SLIM-GOAL.md rule 9, and it cost two whole runs to learn.  Bracing ran
# before macro expansion, expansion pasted in `for` headers of its own, and
# 1,558 unbraced bodies sat in a file whose documentation said every body was
# braced.  Within this phase the same thing happens on a smaller scale: the
# comma hoist puts an initialiser on a new line, which re-shapes the line and
# gives splitheads and brace something new to find, and onestmt splits one
# label off a `case A: case B: case C:` line per pass, so it needs five rounds
# on its own.
#
# So: loop until the file stops changing.  That is stronger than "run each tool
# once and check it reports zero", and it does not depend on parsing seven
# different tools' output.  Each is idempotent and cheap, so a fixpoint costs
# seconds and is a check rather than a change once the file is settled.
#
# Phase 9 calls this too: macro expansion re-breaks exactly what Phase 7 fixed.
set -eu

file=${1:?usage: canon.sh <file>}
here=$(dirname "$0")

round=0
while :; do
    round=$((round + 1))
    before=$(sha256sum "$file" | cut -d' ' -f1)

    python3 "$here/blankruns.py"  "$file" >/dev/null
    python3 "$here/joinparens.py" "$file" >/dev/null
    python3 "$here/splitheads.py" "$file" >/dev/null
    python3 "$here/brace.py"      "$file" >/dev/null
    python3 "$here/onestmt.py"    "$file" >/dev/null
    python3 "$here/onedecl.py"    "$file" >/dev/null
    python3 "$here/forcomma.py"   "$file" >/dev/null

    after=$(sha256sum "$file" | cut -d' ' -f1)
    [ "$before" = "$after" ] && break

    if [ "$round" -ge 20 ]; then
        echo "  canon        NOT CONVERGING after $round rounds -- two passes are"
        echo "               undoing each other; that is a bug in one of them,"
        echo "               not a reason to raise the limit."
        exit 1
    fi
done

echo "  canon        fixpoint after $round round$([ "$round" = 1 ] || echo s)"
