#!/bin/sh
# Phase 3 -- one Makefile, nothing generated.  See GOAL.md.
#
# Usage: tools/phase3.sh <work-dir>       (run from the repository root)
#
# Five edits, all mechanical, and the boundary diff between phase 2 and phase 3
# is exactly these: vim.h, xdiff.h, proto.h, a new Makefile and no more
# config.mk.  3,570 lines of autoconf output become 65.
#
# Getting -I and -D off the compile line is what the three source edits are
# for, and none of them is a relocation:
#
#   * -DHAVE_CONFIG_H guards a fifty-line block in vim.h, and the block has to
#     be UNWRAPPED.  Deleting only the opening line leaves its #endif to close
#     #ifndef VIM__H three thousand lines early, and what gcc then reports is a
#     redeclared enumerator in termdefs.h, a file with no connection to any of
#     it.  tools/unwrapif.py matches instead of substituting.
#   * -Iproto is two things.  proto.h names its 97 .pro includes by path, and
#     xdiff.h's "../vim.h" -- which only ever resolved because -Iproto made
#     proto/../vim.h mean this directory -- names it directly.
#   * -lm is not needed at all under musl, whose libm is part of libc, so there
#     is nothing to move into LDLIBS.  Another libc would want it back.
#
# The makefile itself is a checked-in template rather than something generated:
# it uses $(wildcard), so it bakes in no file list and has nothing to compute.
# Keeping it as text also keeps a pass from rewriting its prose slightly
# differently every time, which is a boundary difference that means nothing and
# has to be explained anyway.
set -eu

work=${1:?usage: phase3.sh <work-dir>}
jobs=$(nproc 2>/dev/null || echo 4)

# --- the three source edits ----------------------------------------------
python3 tools/unwrapif.py "$work/vim.h" HAVE_CONFIG_H

# The .pro includes are indented four different ways -- 65 with one space, 24
# with two, 6 with three, 3 with four -- because they sit at different
# conditional depths.  An anchored two-space pattern rewrites 23 of 98 and the
# build then fails on the first file it did not touch, which is a long way from
# the mistake.  Keep whatever indentation each line has, and count.
before=$(grep -c '^#[ ]*include "[a-z0-9_]*\.pro"' "$work/proto.h" || true)
sed -i 's|^#\([ ]*\)include "\([a-z0-9_]*\.pro\)"|#\1include "proto/\2"|' "$work/proto.h"
after=$(grep -c '^#[ ]*include "proto/[a-z0-9_]*\.pro"' "$work/proto.h" || true)
if [ "$before" != "$after" ] || [ "$before" -lt 90 ]; then
    echo "  proto.h      $before found, $after rewritten -- expected all of ~98."
    echo "               A pattern that stops matching yields a tree that fails"
    echo "               to build on the first file it missed, so this is a hard"
    echo "               error rather than a count to eyeball."
    exit 1
fi
echo "  proto.h      $after .pro includes named by path"

sed -i 's|^# include "\.\./vim\.h"|# include "vim.h"|' "$work/xdiff.h"
echo "  xdiff.h      ../vim.h names this directory directly"

# --- the makefile ---------------------------------------------------------
cp tools/templates/upstream.mk "$work/Makefile"
rm -f "$work/config.mk"
echo "  Makefile     $(grep -c '' tools/templates/upstream.mk) lines, and no config.mk"

# --- it has to build ------------------------------------------------------
# The phase is not "the files were edited", it is "the tree still compiles with
# no -I, no -D and no generated file".  Nothing else here proves that.
make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" -j"$jobs" >/dev/null 2>&1; then
    echo "  build        ok, with no -I, no -D and nothing generated"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi
