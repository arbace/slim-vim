#!/bin/sh
# Snapshot a work tree, and digest it by content rather than by packaging.
#
# Usage: tools/snapshot.sh <dir> <out.tar> <out.sha256>
#
# The digest is a sha256 over a sorted "sha256␠path" listing, NOT over the tar.
# That matters: tar bytes carry mtimes, uid/gid, ordering and format quirks,
# none of which are the tree, and every one of which would make a boundary
# compare unequal for a reason that is not a difference in the source.  The tar
# is only a restore point.
#
# The tar is still written deterministically, so that two snapshots of the same
# tree are the same file and a stale one is visible as one.
set -eu

dir=${1:?usage: snapshot.sh <dir> <out.tar> <out.sha256>}
tar_out=${2:?}
sha_out=${3:?}

mkdir -p "$(dirname "$tar_out")"

# What the digest counts is the SOURCE, not what building it left behind.
#
# The tar keeps everything, because a restore has to hand the next phase a tree
# it can build on without a nine-second rebuild.  The digest excludes what a
# build writes, for two separate reasons: config.log and config.status carry
# timestamps and the invoking command line, so a boundary containing them is
# never equal to itself twice; and objects/ plus the binary are a function of
# the sources already, so counting them says nothing new while making every
# boundary 30 MB of noise.
#
# Anything that survives into vim.c stays counted -- auto/config.h and
# auto/pathdef.c are generated too, but Phase 1 freezes them as sources and
# their content is part of the answer.
exclude='/objects/|/auto/config\.(log|status|cache)$|\.(o|d)$|/src/vim$'

# find | sort makes the order the tree's, not the filesystem's.
( cd "$dir" && find . -type f ! -path './.git/*' -print0 \
    | sort -z \
    | xargs -0 sha256sum ) | grep -Ev "$exclude" > "$sha_out.files"
sha256sum < "$sha_out.files" | cut -d' ' -f1 > "$sha_out"

tar --create --file "$tar_out" \
    --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    --format=gnu --exclude=.git -C "$dir" .

printf '  %-12s %s  %s files, %s\n' "snapshot" \
    "$(cut -c1-12 "$sha_out")" \
    "$(grep -c '' "$sha_out.files")" \
    "$(du -h "$tar_out" | cut -f1)"
