#!/bin/sh
# Build the corpora the Go tools are judged against.  Run from the repository
# root, with the boundaries of a pass already in .build-whim, .build-zero and
# .build-slim.
#
# Usage: tools/gocorpus.sh <outdir> [--unswept]
#
# Three corpora, and the reason there are three is the whole lesson of this
# harness:
#
#   <outdir>/wz       every .c from every whim and zero boundary.  These are
#                     the sweep's OUTPUT -- sweep.sh only terminates on a round
#                     that changed nothing, and canon.sh --once is the last
#                     member of that round -- so they are already canonical and
#                     a canonicaliser finds NOTHING in them.  Measured: the
#                     first run of difftest agreed on 59 of 59 of these, and so
#                     did a deliberately broken build, on 58.  Necessary, and
#                     on its own it proves almost nothing.
#
#   <outdir>/unswept  the output of real phase -edit.sh programs, run on the
#                     boundary before each.  This is what a tool in the sweep
#                     is actually handed: text a cut has just been made in and
#                     nothing has compiled since.  Built only with --unswept,
#                     because it runs the pipeline's own programs and costs
#                     minutes rather than seconds.
#
#   <outdir>/slim     slim's merged vim.c at p6..p11, plus its per-file
#                     src/*.c.  OUT OF SCOPE as a product -- the Go tools are
#                     for whim and zero -- and indispensable as a test corpus,
#                     because it is the only text that exercises the paths
#                     whim and zero never reach: line-spanning parenthesised
#                     groups, unbraced bodies, #define, #if, tabs.  A Go tool
#                     that only ever ran on whim/zero text would have most of
#                     its code unexecuted by every test.
#
# Nothing here is written into the repository; the output directory is yours.
set -eu

out=${1:?usage: tools/gocorpus.sh <outdir> [--unswept]}
unswept=${2:-}

[ -d tools ] && [ -d pipes ] || { echo "gocorpus: run me from the repository root" >&2; exit 1; }

mkdir -p "$out/wz" "$out/slim"

# One .c per whim and zero boundary, named for the boundary so a failure names
# a phase.  input.tar is skipped: it is q0's input and byte-identical to it.
for pipe in whim zero; do
    [ -d ".build-$pipe" ] || continue
    for t in ".build-$pipe"/*.tar; do
        [ -f "$t" ] || continue
        b=$(basename "$t" .tar)
        [ "$b" = input ] && continue
        d=$(mktemp -d)
        tar xf "$t" -C "$d" 2>/dev/null || { rm -rf "$d"; continue; }
        for c in "$d"/*.c "$d"/./*.c; do
            [ -f "$c" ] || continue
            cp "$c" "$out/wz/$pipe-$b.c"
        done
        rm -rf "$d"
    done
done

# slim's merged single file, which is what canon.sh and the sweep really see,
# and its per-file sources, which carry the directives.
if [ -d .build-slim ]; then
    for t in .build-slim/*.tar; do
        [ -f "$t" ] || continue
        b=$(basename "$t" .tar)
        [ "$b" = input ] && continue
        d=$(mktemp -d)
        tar xf "$t" -C "$d" 2>/dev/null || { rm -rf "$d"; continue; }
        if [ -f "$d/vim.c" ]; then
            cp "$d/vim.c" "$out/slim/$b-vim.c"
        elif [ -d "$d/src" ]; then
            for c in "$d"/src/*.c; do
                [ -f "$c" ] || continue
                cp "$c" "$out/slim/$b-$(basename "$c")"
            done
        fi
        rm -rf "$d"
    done
fi

# The corpus that costs minutes: run each split phase's EDIT on the boundary
# before it, and keep what it leaves.  The edit's contract is
# `pipes/<impl><N>-edit.sh <work> <state>`, with the state directory seeded by
# the driver with the line count of the text the edit is handed.  An edit that
# wants more than that -- a symbol snapshot, a previous binary -- is skipped
# here rather than faked, and says so.
if [ "$unswept" = "--unswept" ]; then
    mkdir -p "$out/unswept"
    for pipe in whim zero; do
        case $pipe in
            whim) tag=q; impl=whim ;;
            zero) tag=r; impl=zero ;;
        esac
        [ -d ".build-$pipe" ] || continue
        for e in pipes/$impl*-edit.sh; do
            [ -f "$e" ] || continue
            n=$(basename "$e" -edit.sh); n=${n#$impl}
            prev=$((n - 1))
            t=".build-$pipe/$tag$prev.tar"
            [ -f "$t" ] || continue
            work=$(mktemp -d); state=$(mktemp -d)
            tar xf "$t" -C "$work" 2>/dev/null || { rm -rf "$work" "$state"; continue; }
            c=$(find "$work" -maxdepth 1 -name '*.c' | head -1)
            [ -n "$c" ] || { rm -rf "$work" "$state"; continue; }
            wc -l < "$c" > "$state/input-lines"
            mkdir -p "$state/symbols"
            if "$e" "$work" "$state" >/dev/null 2>&1; then
                c=$(find "$work" -maxdepth 1 -name '*.c' | head -1)
                [ -n "$c" ] && cp "$c" "$out/unswept/$pipe$n.c"
            else
                echo "  gocorpus     $impl$n edit declined its input, skipped" >&2
            fi
            rm -rf "$work" "$state"
        done
    done
fi

printf 'gocorpus: wz %s, slim %s' "$(ls "$out/wz" | wc -l)" "$(ls "$out/slim" | wc -l)"
[ -d "$out/unswept" ] && printf ', unswept %s' "$(ls "$out/unswept" | wc -l)"
printf '\n'
