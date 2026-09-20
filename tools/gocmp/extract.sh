#!/bin/sh
# Extract the single .c from every whim and zero boundary tar into a flat
# corpus directory, named after its boundary so a failure names a phase.
set -eu
root=/root/slim-vim/.claude/worktrees/go-tools
out=${GOCMP:-tools/gocmp}/corpus
rm -rf "$out"
mkdir -p "$out"

for pipe in whim zero; do
    for tar in "$root/.build-$pipe"/*.tar; do
        b=$(basename "$tar" .tar)
        [ "$b" = input ] && continue
        d=$(mktemp -d)
        tar xf "$tar" -C "$d" --wildcards './*.c' 2>/dev/null || { rm -rf "$d"; continue; }
        for c in "$d"/*.c; do
            [ -f "$c" ] || continue
            cp "$c" "$out/$pipe-$b.c"
        done
        rm -rf "$d"
    done
done

ls "$out" | wc -l
du -sh "$out"
