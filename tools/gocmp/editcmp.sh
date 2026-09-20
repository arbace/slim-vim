#!/bin/sh
# One zero edit heredoc against its Go port: same input, same tree out, same
# report, same state directory, byte for byte.
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
# THE HEREDOC IS NOT ALWAYS THE WHOLE EDIT, which is what the state directory
# is for.  Four zero phases hand their heredoc a second argument -- zero26 a
# FILE it reads (`$state/minmax.txt`, the MIN/MAX expansion read back through
# the preprocessor) and zero27, zero35 and zero36 the DIRECTORY, into which
# zero35 writes two files its check then reads.  So an argument list is lifted
# out of the phase program's own `python3 - ` line and given to both sides, the
# shell that PRODUCES those files is run once per side when some heredoc wants
# it, and the two state directories are compared at the end like the tree.
# Running the prefix is skipped when no heredoc mentions `$state`, which is the
# common case and the one that has to stay fast.
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

    d=$work/$phase; rm -rf "$d"; mkdir -p "$d/py" "$d/go" "$d/pystate" "$d/gostate"
    tar xf "$tar" -C "$d/py"
    tar xf "$tar" -C "$d/go"

    # EVERY heredoc, lifted out of the phase program, each to its own file and
    # run in order.  `exit` on the first closing PY was wrong: pipes/zero12-edit.sh
    # holds TWO, and a checker that took only the first would run the Python
    # halfway and the Go all the way, reporting a difference that is the
    # checker's.  A heredoc's POSITION in the phase program is part of the
    # phase -- the other session hit the same shape in whim, where two heredocs
    # stand after a dropoptions call and folding them into one would move the
    # cut earlier.
    awk -v out="$d" "
        /<<'PY'\$/ { n++; f = 1; next }
        f && /^PY\$/ { f = 0; next }
        f { print > (out \"/edit\" n \".py\") }
    " "$prog"
    cat "$d"/edit*.py > "$d/edit.py" 2>/dev/null || true
    # A PHASE ALREADY PORTED HAS NO HEREDOC LEFT, and that is not a failure:
    # the swap is what removes it, so from then on the boundary gate is the
    # only check there is.  It IS a failure if there is no Go edit either,
    # because then nothing at all is being compared.
    if [ ! -s "$d/edit.py" ]; then
        # Tested as a FILE rather than by asking the binary, so this needs no
        # change to cmd/slimtools/edit.go -- which is the other session's, and
        # the one file a shared edit would collide on.
        if [ -f "tools/go/internal/edit/$phase.go" ]; then
            printf 'ported %-8s no heredoc left; `make %s` is its only gate now\n' \
                "$phase" "$(echo "$phase" | sed 's/zero/zero-phase-/')"
        else
            echo "editcmp: $phase has neither a PY heredoc nor a Go edit" >&2
            rc=1
        fi
        continue
    fi

    # THE ARGUMENT LIST IS THE PHASE PROGRAM'S OWN, one per heredoc and in the
    # same order, read off the `python3 - ` line with the redirection stripped.
    # It is `eval`ed rather than parsed so that `"$f"` and `"$state/minmax.txt"`
    # mean here what they mean there.
    sed -n 's/^python3 - \(.*\)<<.PY.$/\1/p' "$prog" > "$d/args"
    nargs=$(grep -c '' "$d/args" || true)
    nparts=$(ls "$d"/edit[0-9]*.py | grep -c '' || true)
    if [ "$nargs" != "$nparts" ]; then
        printf 'DIFFER %-8s %s heredocs but %s `python3 - ` lines\n' "$phase" "$nparts" "$nargs"
        rc=1
        continue
    fi

    # The shell that produces the state directory, run once per side and only
    # when a heredoc actually wants one.  It is the phase program up to its
    # first heredoc, which is where every $state file is written; the tail
    # after the heredoc is the wait and the report and is not an input.
    if grep -q 'state' "$d/args"; then
        head -n "$(( $(grep -n '^python3 - ' "$prog" | head -1 | cut -d: -f1) - 1 ))" \
            "$prog" > "$d/prefix.sh"
        for side in py go; do
            if ! sh -eu "$d/prefix.sh" "$d/$side" "$d/${side}state" > "$d/$side.prefix" 2>&1; then
                printf 'DIFFER %-8s the phase program prefix failed for %s\n' "$phase" "$side"
                head -5 "$d/$side.prefix"
                rc=1
                continue 2
            fi
        done
    fi

    # BOTH RUN FROM THE REPOSITORY ROOT, on an absolute path.  The heredoc does
    # `sys.path.insert(0, 'tools')` and then `import cutil`, which is relative
    # to the CWD -- run it from a scratch directory and it dies in the import
    # rather than in the edit, which reads as a difference and is not one.
    prc=0; grc=0; i=0
    for part in "$d"/edit[0-9]*.py; do
        i=$((i + 1))
        line=$(sed -n "${i}p" "$d/args")

        f=$d/py/zero-vim.c; state=$d/pystate
        eval "set -- $line"
        python3 "$part" "$@" >> "$d/py.out" 2>&1 || { prc=$?; break; }

        f=$d/go/zero-vim.c; state=$d/gostate
        eval "set -- $line"
        "$bin" edit "$phase" "$@" >> "$d/go.out" 2>&1 || { grc=$?; break; }
    done
    touch "$d/py.out" "$d/go.out"

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
    # The state directory is compared like the tree, because for zero35 it IS
    # part of the edit's output -- `block-before` and `block-after`, which its
    # check reads.  `old.c` and `old` are the prefix's and are excluded: they
    # are a copy of the input and a build of it, identical by construction and
    # 800 KB each to compare.
    if ! diff -r -x old.c -x old -x 'minmax-probe*' "$d/pystate" "$d/gostate" > "$d/state.diff" 2>&1; then
        printf 'DIFFER %-8s the state directory\n' "$phase"
        head -12 "$d/state.diff"
        rc=1
        continue
    fi
    printf 'same   %-8s tree and report, %s lines of report, exit %s\n' \
        "$phase" "$(grep -c '' "$d/py.out")" "$prc"
done
exit "$rc"
