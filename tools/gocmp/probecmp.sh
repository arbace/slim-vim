#!/bin/sh
# The four probes -- starcheck, complcheck, termrestore, clicheck -- Go against
# Python, on binaries chosen so that EACH ARM of each probe is exercised.
#
# Usage: sh tools/gocmp/probecmp.sh        (run from the repository root)
#
# A PROBE'S ANSWER IS ONE BIT, so agreement on one binary is the weakest
# evidence in this directory.  Two implementations that both always said "pass"
# would agree perfectly.  So every probe is run on a binary that must PASS and
# one that must FAIL, and the run refuses unless it saw both -- and what is
# compared is not the bit but the whole diagnostic, byte for byte, because that
# is where a port actually differs.  It already caught two real differences:
#   - Python's %r is single-quoted and Go's %q is double, so starcheck's
#     complaint differed in nothing but the shape of a quote (see pyRepr);
#   - the Go runner printed the error it returned on top of the diagnostics the
#     tool had already written, one line the Python does not have (ErrReported).
#
# THE THREE PRODUCTS ARE THE CONTROLS, which costs nothing to arrange because
# the pipeline already made them differ in exactly the right places:
#   starcheck    whim-vim passes; zero-vim takes no file argument since its
#                phase 5, so the buffer is untouched and it must fail
#   complcheck   whim-vim passes; slim-vim predates whim phase 32, so CTRL-X
#                CTRL-N really completes there and it must fail
#   termrestore  whim-vim passes; /bin/cat never enters raw mode, which trips
#                the probe's OWN vacuity guard and must fail
#   clicheck     slim-vim has every option, so all 30 dropped ones are wrong;
#                whim-vim has had most of the kept ones removed by later
#                phases.  Both must fail, and identically -- this is the one
#                probe with no passing binary in the tree, and it is reported
#                as such rather than papered over.
set -eu

[ -d tools ] && [ -d pipes ] || { echo "probecmp: run me from the repository root" >&2; exit 1; }
bin=$PWD/$(sh tools/gobuild.sh)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "building the three products" >&2
SOURCE_DATE_EPOCH=0 gcc -O0 -static -s -o "$work/slim-vim" slim-vim.c
SOURCE_DATE_EPOCH=0 gcc -O0 -static -s -o "$work/whim-vim" whim-vim.c
SOURCE_DATE_EPOCH=0 gcc -O0 -fno-stack-protector -static -no-pie -s -o "$work/zero-vim" zero-vim.c

same=0; differ=0; passes=0; fails=0

one() {   # one <probe> <binary> <label>
    probe=$1; target=$2; label=$3
    python3 "tools/$probe.py" "$target" > "$work/py" 2>&1 && prc=0 || prc=$?
    "$bin" "$probe" "$target" > "$work/go" 2>&1 && grc=0 || grc=$?
    if [ "$prc" = 0 ]; then passes=$((passes + 1)); else fails=$((fails + 1)); fi
    if [ "$prc" = "$grc" ] && cmp -s "$work/py" "$work/go"; then
        same=$((same + 1))
        printf '  same   %-12s %-10s rc=%s\n' "$probe" "$label" "$prc"
    else
        differ=$((differ + 1))
        printf '  DIFFER %-12s %-10s python rc=%s go rc=%s\n' "$probe" "$label" "$prc" "$grc"
        diff "$work/py" "$work/go" | head -8
    fi
}

one starcheck   "$work/whim-vim" whim-vim
one starcheck   "$work/zero-vim" zero-vim
one complcheck  "$work/whim-vim" whim-vim
one complcheck  "$work/slim-vim" slim-vim
one termrestore "$work/whim-vim" whim-vim
one termrestore /bin/cat         cat
one clicheck    "$work/slim-vim" slim-vim
one clicheck    "$work/whim-vim" whim-vim

echo "probecmp: $same same, $differ differ -- $passes runs the Python passed, $fails it refused"
[ "$differ" -eq 0 ] || exit 1
[ "$passes" -gt 0 ] || { echo "probecmp: no probe passed on any binary - the pass arm was never exercised" >&2; exit 1; }
[ "$fails" -gt 0 ]  || { echo "probecmp: no probe failed on any binary - the fail arm was never exercised" >&2; exit 1; }
