#!/bin/sh
# One zero edit heredoc against its Go port: same input, same tree out, same
# report, byte for byte.
#
# Usage: sh tools/gocmp/editcmp.sh zero2 [zero6 ...]   (from the repository root)
#
# WHY THIS AND NOT JUST `make zero-phase-N`.  The boundary gate is the real
# one and it is what says a port is done -- but it runs the whole phase, sweep
# and check and recording included, and when it fails it says the digest moved.
# This says WHICH ACT diverged, in seconds, by comparing the two reports line
# by line; and it compares the tree before any sweep has touched it, so a
# difference cannot be absorbed by a canonicaliser.
#
# ORDER IS OUTPUT, so the report is compared as a sequence and not as a set.
# That is the whole reason the report is compared at all: a Go port that groups
# edits of the same shape into a loop produces a byte-identical tree and a
# differently-ordered log, which the boundary gate cannot see and a human
# comparing two phase commits certainly can.
#
# The Python is run by extracting the heredoc from the phase program rather
# than by running the phase, because the phase also builds binaries, starts
# background jobs and reads a state directory.  What is wanted is the edit.
set -eu

[ -d tools ] && [ -d pipes ] || { echo "editcmp: run me from the repository root" >&2; exit 1; }
bin=$PWD/$(sh tools/gobuild.sh)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
rc=0

for phase in "$@"; do
    prog=pipes/$phase-edit.sh
    [ -f "$prog" ] || { echo "editcmp: no $prog" >&2; rc=1; continue; }
    n=${phase#zero}
    prev=$((n - 1))
    tar=.build-zero/r$prev.tar
    [ -f "$tar" ] || { echo "editcmp: $phase wants $tar, which is not here" >&2; rc=1; continue; }

    d=$work/$phase; rm -rf "$d"; mkdir -p "$d/py" "$d/go"
    tar xf "$tar" -C "$d/py"
    tar xf "$tar" -C "$d/go"

    # The heredoc, lifted out of the phase program.  Everything between the
    # line that opens it and the lone PY that closes it.
    awk "/<<'PY'\$/{f=1;next} f&&/^PY\$/{exit} f{print}" "$prog" > "$d/edit.py"
    [ -s "$d/edit.py" ] || { echo "editcmp: $phase has no PY heredoc" >&2; rc=1; continue; }

    # BOTH RUN FROM THE REPOSITORY ROOT, on an absolute path.  The heredoc does
    # `sys.path.insert(0, 'tools')` and then `import cutil`, which is relative
    # to the CWD -- run it from a scratch directory and it dies in the import
    # rather than in the edit, which reads as a difference and is not one.
    python3 "$d/edit.py" "$d/py/zero-vim.c" > "$d/py.out" 2>&1 && prc=0 || prc=$?
    "$bin" edit "$phase" "$d/go/zero-vim.c" > "$d/go.out" 2>&1 && grc=0 || grc=$?

    if [ "$prc" != "$grc" ]; then
        printf 'DIFFER %-8s exit: python=%s go=%s\n' "$phase" "$prc" "$grc"
        echo "  py: $(head -3 "$d/py.out" | tr '\n' ' | ')"
        echo "  go: $(head -3 "$d/go.out" | tr '\n' ' | ')"
        rc=1
        continue
    fi
    if ! cmp -s "$d/py/zero-vim.c" "$d/go/zero-vim.c"; then
        printf 'DIFFER %-8s the tree\n' "$phase"
        diff "$d/py/zero-vim.c" "$d/go/zero-vim.c" | head -12
        rc=1
        continue
    fi
    if ! cmp -s "$d/py.out" "$d/go.out"; then
        printf 'DIFFER %-8s the report\n' "$phase"
        diff "$d/py.out" "$d/go.out" | head -12
        rc=1
        continue
    fi
    printf 'same   %-8s tree and report, %s lines of report, exit %s\n' \
        "$phase" "$(grep -c '' "$d/py.out")" "$prc"
done
exit "$rc"
