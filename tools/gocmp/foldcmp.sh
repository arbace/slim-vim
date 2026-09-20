#!/bin/sh
# cutil's fold primitives against the Python's, on real patterns taken from
# the phase programs that use them.
set -eu
cd /root/slim-vim/.claude/worktrees/go-tools
bin=$(sh tools/gobuild.sh)
same=0; diff=0

try() {   # try <kind> <input.c> <pattern> <count>
    kind=$1; src=$2; pat=$3; n=$4
    a=$(mktemp); b=$(mktemp)
    cp "$src" "$a"; cp "$src" "$b"
    pa=$(python3 -c "
import re, sys
sys.path.insert(0, 'tools')
import cutil
kind, path, pat, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
s = open(path, encoding='utf-8', errors='surrogateescape').read()
fn = {'always': cutil.fold_always, 'never': cutil.fold_never, 'dropif': cutil.drop_if}[kind]
try:
    s = fn(s, pat, n, re.M)
except ValueError as e:
    print(e); sys.exit(1)
open(path, 'w', encoding='utf-8', errors='surrogateescape').write(s)
" "$kind" "$a" "$pat" "$n" 2>&1 || echo "EXIT$?")
    pb=$(./"$bin" fold "$kind" "$b" "(?m)$pat" "$n" 2>&1 || echo "EXIT$?")
    if [ "$pa" = "$pb" ] && cmp -s "$a" "$b"; then
        same=$((same + 1)); printf '  %-7s %-46s same\n' "$kind" "$(echo "$pat" | cut -c1-46)"
    else
        diff=$((diff + 1)); printf '  %-7s %-46s DIFFER\npy: %s\ngo: %s\n' "$kind" "$(echo "$pat" | cut -c1-46)" "$pa" "$pb"
        cmp -s "$a" "$b" || echo "  (output files differ)"
    fi
    rm -f "$a" "$b"
}

W=${GOCMP_CORPUS:-.cache/gocorpus}/wz
# Real patterns, from tools/noabbr.py.
try never "$W/whim-q0.c" '^[ \t]*if \(echeck_abbr\(ESC \+ ABBR_OFF\)\)$' 1
try never "$W/whim-q0.c" '^[ \t]*if \(ccheck_abbr\(c \+ ABBR_OFF\)\)$' 1
# A pattern that matches the wrong number of times must refuse.
try never "$W/whim-q0.c" '^[ \t]*if \(echeck_abbr\(' 1
# And one that is not there at all.
try dropif "$W/whim-q0.c" '^[ \t]*if \(no_such_condition_9x\)$' 1

echo "fold: $same same, $diff differ"
[ "$diff" -eq 0 ]
