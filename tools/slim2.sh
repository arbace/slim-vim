#!/bin/sh
# Phase 2 -- prune the tree to what the compiler opens.  See SLIM-GOAL.md.
#
# Usage: tools/slim2.sh <work-dir>       (run from the repository root)
#
# 8,574 files become 165, and almost none of that is a list to maintain: what
# survives is COMPUTED, twice over, by asking the compiler.
#
#   * A source whose object defines no symbols compiles to nothing and cannot
#     be contributing to the link.  61 of 128 here -- the whole eval layer, all
#     nine vim9*.c, syntax.c, quickfix.c, the spell and terminal code.  This
#     removes no feature; there is nothing there to remove.
#   * A file the compiler never opened is not needed.  The -MD dependency files
#     record exactly that, and they are the only right answer: `make -p`
#     returns the whole rule database, including rules for the GUI, perl,
#     wayland and libvterm this build never reaches -- 441 entries against 254,
#     and the extra 187 are junk.
#
# The order matters and SLIM-GOAL.md is emphatic about it: drop the empty objects
# FIRST, then measure the keep-set once.  Measuring before the drop answers a
# question about a tree that is about to change.
#
# LICENSE is the one file kept for its own sake: clause II.1 requires Vim's
# licence in a modified Vim, and the headers that carried the attribution go
# with the comments in Phase 4.
set -eu

work=${1:?usage: phase2.sh <work-dir>}
src="$work/src"
jobs=$(nproc 2>/dev/null || echo 4)

# --- keep LICENSE and src/, and nothing else ------------------------------
# Not runtime/, src/testdir/, the docs, xxd, libvterm, po/, the CI
# configuration or the upstream dotfiles.  There is no git metadata to keep --
# upstream/.git went before any of this started.
find "$work" -mindepth 1 -maxdepth 1 ! -name src ! -name LICENSE -exec rm -rf {} +
find "$src" -mindepth 1 -maxdepth 1 -type d \
     ! -name proto ! -name auto ! -name xdiff ! -name objects -exec rm -rf {} +
echo "  top level    LICENSE and src/ kept"

# --- what the sources actually ARE ----------------------------------------
# Not every .c here is one: the GUI, the language bindings and three other
# platforms are still present and configure never selected them.  The
# authoritative list is the set of objects the previous phase's build left --
# computed, not parsed out of a 4,910-line makefile, and correct by
# construction.
# auto/pathdef.c is the one source that is not in this directory, and an object
# name maps to a source name only once it is.  The flatten below would move it
# anyway; doing it here costs nothing and keeps SRC uniform.
mv "$src"/auto/*.c "$src"/ 2>/dev/null || true

srcs() {
    for o in "$src"/objects/*.o; do
        [ -f "$o" ] || continue
        printf '%s.c ' "$(basename "$o" .o)"
    done
}
write_srcs() { printf 'SRC = %s\n' "$(srcs)" > "$src/srcs.mk"; }

write_srcs
echo "  sources      $(srcs | wc -w | tr -d ' ') of $(ls "$src"/*.c | wc -l | tr -d ' ') .c files are in this build"

# --- our own makefile, so there is no surgery to do -----------------------
cp tools/templates/pruned.mk "$src/Makefile"
rm -f "$src/config.mk"

# --- the empty objects ----------------------------------------------------
make -C "$src" compile -j"$jobs" >/dev/null 2>&1

empty=$(for o in "$src"/objects/*.o; do
            [ -f "$o" ] || continue
            if [ -z "$(nm --defined-only "$o" 2>/dev/null)" ]; then
                basename "$o" .o
            fi
        done)
n_empty=$(echo "$empty" | grep -c '[a-z]' || true)

# Removing a .c takes the source, its .pro, and -- the one that bites -- the
# #include of that .pro in proto.h.  proto.h writes them "clientserver.pro",
# not "proto/clientserver.pro", so a grep for the latter finds nothing and
# reports the job done; the build then fails in every remaining translation
# unit at once.
for name in $empty; do
    rm -f "$src/$name.c" "$src/proto/$name.pro" "$src/objects/$name.o" \
          "$src/objects/$name.d"
    sed -i "/^#[ ]*include \"$name\.pro\"/d" "$src/proto.h"
done
write_srcs
echo "  empty        $n_empty sources compiled to nothing, and are gone"

# --- the keep-set, measured once, after the drop --------------------------
make -C "$src" clean >/dev/null 2>&1
make -C "$src" compile -j"$jobs" >/dev/null 2>&1

keep=$(mktemp)
trap 'rm -f "$keep"' EXIT
python3 - "$src" "$src/objects" "$keep" <<'PY'
import os, sys
sys.path.insert(0, 'tools')
import keepset
src, objdir, out = sys.argv[1], sys.argv[2], sys.argv[3]
names = keepset.from_depfiles(objdir, src)
open(out, 'w').write('\n'.join(sorted(names)) + '\n')
print('  keep-set     %d files the compiler opened' % len(names))
PY

# Everything the compiler never opened goes -- except the makefile, the licence
# and the objects we are still standing on.
# Anchor these by PATH, not by name.  src/auto/wayland/ ships a Makefile of
# its own, and a `! -name Makefile` exemption keeps it -- after which the
# flatten moves it over the one this phase just installed, and the build stops
# at "No rule to make target 'vim'" with a wayland protocols makefile in place.
find "$src" -type f \
     ! -path "$src/objects/*" ! -path "$src/Makefile" ! -path "$src/srcs.mk" \
     ! -path "$src/LICENSE" \
     | while read -r f; do
    rel=${f#"$src"/}
    grep -qxF "$rel" "$keep" || rm -f "$f"
done
echo "  pruned       $(find "$src" -type f ! -path "$src/objects/*" | wc -l | tr -d ' ') files left"

# --- flatten --------------------------------------------------------------
# Every tool from here on takes a path, and one directory level is one fewer
# thing for each of them to be wrong about.  proto/ stays until Phase 6.
#
# Check who includes a file before moving it: xdiff/xdiff.h was once moved on
# the assumption that diff.c was the consumer.  diff.c had already gone as an
# empty object, and the real include is in vim.h, unconditionally, for mmfile_t.
for d in auto xdiff; do
    [ -d "$src/$d" ] || continue
    find "$src/$d" -maxdepth 1 -type f -exec mv -t "$src" {} + 2>/dev/null || true
    rm -rf "$src/$d"
done
# The includes, and the one diagnostic that names a directory which no longer
# exists.  config.h's own first line still says "auto/config.h. Generated from
# config.h.in" and is left alone: that is a provenance note, not a path anyone
# follows.
sed -i -e 's|include "auto/|include "|' -e 's|include "xdiff/|include "|' -e 's|Check auto/config\.log|Check config.log|' "$src"/*.h "$src"/*.c
mv "$src"/* "$work"/ 2>/dev/null || true
rmdir "$src"
echo "  flattened    src/ is gone, proto/ stays until Phase 6"

# --- and it still links ---------------------------------------------------
make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" vim -j"$jobs" >/dev/null 2>&1; then
    rm -f "$work/srcs.mk"        # scaffolding; the makefile that replaces this
    echo "  build        ok, $(find "$work" -type f ! -path "$work/objects/*" | wc -l | tr -d ' ') files"
else
    echo "  build        FAILED -- rerun by hand: make -C $work vim"
    exit 1
fi
