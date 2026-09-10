#!/bin/sh
# Put a work tree back to a snapshot, so a phase is a pure function of its
# input rather than of whatever the last run left lying about.
#
# Usage: tools/restore.sh <in.tar> <dir>
#
# The directory is emptied first.  A phase that deletes a file is as much a
# part of the phase as one that writes it, so unpacking over the top would
# silently keep the deleted file and make the boundary digest disagree for a
# reason nothing in the phase caused.
set -eu

tar_in=${1:?usage: restore.sh <in.tar> <dir>}
dir=${2:?}

rm -rf "$dir"
mkdir -p "$dir"
tar --extract --file "$tar_in" -C "$dir"
