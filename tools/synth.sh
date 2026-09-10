#!/bin/sh
# Memoize an agent's behaviour as code.
#
# Usage: tools/synth.sh <phase> <build-dir>
#
# Called after a tier-1 run.  It has the tree the phase was given and the tree
# the phase produced, and the difference between them IS the phase -- so it
# writes that difference out as a patch and, if the phase has no program at
# all, writes the program that applies it.
#
# The result is a legitimate tier 2 and a poor one.  A patch reproduces exactly
# one transformation of exactly one input; it says nothing about why, and it
# fails the moment upstream edits a line it touches.  That failure is not a
# defect -- it is the construct working, because a tier-2 failure falls through
# to tier 1, which produces a new answer and a new patch.
#
# What makes it worth having anyway is that it is FREE and it is a floor.  From
# the first agent run onwards the phase has a fast path, and the work left is
# not "write a program" but "make this patch smaller": replace a hunk with the
# rule that produces it, and the residue shrinks.  tools/residue.sh is the
# scoreboard, and a phase whose residue reaches zero is one that is genuinely
# understood rather than merely recorded.
#
# Existing programs are never overwritten.  A phase that already has algorithms
# gets its residue rewritten instead -- the difference between what the
# algorithms produced and what the agent produced -- which is exactly the thing
# to attack next.
set -eu

phase=${1:?usage: synth.sh <phase> <build-dir>}
build=${2:?}

prog="tools/phase$phase.sh"
residue="tools/patches/p$phase-residue.patch"
mkdir -p tools/patches

before="$build/p$(($phase - 1)).tar"
[ -f "$before" ] || before="$build/input.tar"
after="$build/p$phase.tar"

[ -f "$before" ] && [ -f "$after" ] || {
    echo "  synth        p$phase: no boundaries to diff, nothing to memoize"
    exit 0
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/a" "$tmp/b"
tar xf "$before" -C "$tmp/a"
tar xf "$after" -C "$tmp/b"

# Build artifacts are not the phase.  They are a function of the sources and
# would make the patch enormous and machine-specific at once.
( cd "$tmp" && diff -ruN \
    -x objects -x vim -x 'config.log' -x 'config.status' -x 'config.cache' \
    -x '*.o' -x '*.d' a b > patch ) || true

lines=$(grep -c '' "$tmp/patch" || true)
if [ "$lines" = 0 ]; then
    echo "  synth        p$phase: the agent changed nothing"
    exit 0
fi

mv "$tmp/patch" "$residue"
echo "  synth        p$phase residue: $lines lines, $(grep -c '^--- ' "$residue") files"

if [ -f "$prog" ]; then
    echo "               $prog exists -- its residue is what to attack next"
    exit 0
fi

cat > "$prog" <<EOF
#!/bin/sh
# Phase $phase -- SYNTHESISED from a tier-1 run.  See SLIM-GOAL.md for what the
# phase means; this file only reproduces what an agent did once.
#
# Usage: tools/phase$phase.sh <work-dir>
#
# This is tier 2 in its degenerate form: a patch, and nothing else.  It is
# correct for the input it was recorded from and it will fail on any upstream
# that edits a line it touches -- at which point the memoize falls through to
# tier 1, which produces a new answer and a new patch.
#
# The work is to make the patch smaller.  Replace a hunk with the rule that
# produces it -- a computed set, a table, a transformation over every line of a
# shape -- and leave only what is genuinely a decision.  tools/residue.sh
# reports where each phase stands.
set -eu

work=\${1:?usage: phase$phase.sh <work-dir>}

if ! patch -p1 -d "\$work" --forward --silent < tools/patches/p$phase-residue.patch; then
    echo "  patch        p$phase residue no longer applies -- upstream moved under it"
    exit 1
fi
echo "  patch        p$phase residue applied, $lines lines"
EOF
chmod +x "$prog"
echo "               wrote $prog -- the phase now has a fast path"
