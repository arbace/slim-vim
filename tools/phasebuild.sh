#!/bin/sh
# Build a phase's binary, by linking the object the sweep already compiled when
# there is one for exactly this text.
#
# Usage: tools/phasebuild.sh <work-dir> <lines-before>   (run from the repository root)
#
# Every phase used to end with `make clean && make`: a full compile of a
# 130,000-line translation unit, 5.5 seconds, of text the sweep's last round had
# just compiled.  The sweep's own compile cannot be reused as it is, and that was
# measured rather than assumed: -Wall -Wextra MOVE THE CODE -- the object built
# with them has 64 more bytes of .text and links to a different binary.  So
# tools/sweep.sh also compiles a PLAIN object of each round's starting text, in
# the background, and the round that changes nothing is the round whose object
# is of the final text.  Linked with the work makefile's own flags it is
# byte-identical to what `make` produces (measured with SOURCE_DATE_EPOCH pinned,
# and with the object compiled from a different file name), in a twentieth of a
# second.
#
# The object is used only when its recorded sha is the sha of the file NOW.
# Anything else -- a phase with no sweep, an edit made after the sweep -- builds
# the ordinary way, so this can never link a stale object.
set -eu

work=${1:?usage: phasebuild.sh <work-dir> <lines-before>}
before=${2:?usage: phasebuild.sh <work-dir> <lines-before>}
f="$work/whim-vim.c"

sha=$(sha256sum "$f" | cut -d' ' -f1)
if [ -f .cache/compile/build.o ] && [ "$(cat .cache/compile/build.sha 2>/dev/null)" = "$sha" ]; then
    # The flags are read out of the work makefile rather than written here a
    # second time, so the link cannot drift from what `make` would have done.
    flags=$(make -s -C "$work" -p -n 2>/dev/null | sed -n 's/^CFLAGS = //p; s/^LDFLAGS = //p' | tr '\n' ' ')
    if ! gcc $flags -o "$work/whim-vim" .cache/compile/build.o; then
        echo "  build        FAILED linking the sweep's object"
        exit 1
    fi
    how="linked from the sweep's object"
else
    make -C "$work" clean >/dev/null 2>&1 || true
    if ! make -C "$work" >/dev/null 2>&1; then
        echo "  build        FAILED -- rerun by hand: make -C $work"
        exit 1
    fi
    how="compiled"
fi
echo "  build        ok, $before -> $(grep -c '' "$f") lines, $(stat -c%s "$work/whim-vim") bytes, $how"
