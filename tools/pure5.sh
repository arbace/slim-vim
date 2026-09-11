#!/bin/sh
# Pure phase 5 -- options that accept and do nothing, or only refuse.
# See PURE-GOAL.md.
#
# Usage: tools/pure5.sh <work-dir>       (run from the repository root)
#
# The argument that removed 'spelllang' in phase 2, applied to the command line:
# an option the editor accepts and ignores is a lie, and an option whose whole
# body is an error message is a branch that exists only to say no.  Both are
# better expressed by the option not existing -- a path this build already has,
# mainerr(ME_UNKNOWN_OPTION), reached by anything the parser does not know.
#
#   inert       -f -X -Y --nofork --literal --gui-dialog-file
#   refusing    -A -F -H (not compiled in) and -g (no GUI here)
#   vestigial   --help --version, cut in phase 3 but left as comparisons that
#               matched and then called mainerr
#
# THE DELTA: none the harness records.  It never passes these, so the evidence
# is the score and the error strings leaving the binary.
set -eu

work=${1:?usage: pure3.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")

# --- cut them ------------------------------------------------------------
python3 tools/dropopts.py "$f" \
    -f -X -Y -A -F -H -g \
    --nofork --literal --gui-dialog-file --help --version

# And the advertisement for an option that no longer exists.  mainerr() ends
# every usage error with `More info with: "vim -h"`, which phase 3 made false
# and this phase makes false twice over -- it names a removed option, and it
# names a binary this one is not.  A pointer to nothing is worse than no
# pointer.
python3 - "$f" <<'EOF'
import sys
path = sys.argv[1]
text = open(path, errors='surrogateescape').read()
line = '     fprintf(stderr, "%s", (_("\\nMore info with: \\"vim -h\\"\\n"))) ;\n'
if line not in text:
    sys.exit('pure5: the "More info with" line has moved; it advertises an '
             'option that no longer exists and must not simply be left')
open(path, 'w', errors='surrogateescape').write(text.replace(line, '', 1))
print('  usage        the pointer to a removed -h is gone')
EOF

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
