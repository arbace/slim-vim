#!/bin/sh
# Can the work actually be got out of a git bundle?
#
# Usage: sh tools/gocmp/bundlecheck.sh <bundle> [basis-repo]
#                                              (from the repository root)
#
# WHY THIS EXISTS, and it is the fourth entry on CLAUDE.md's list of checks
# that pass while doing nothing.  `git bundle verify` answers *is this file a
# well-formed bundle whose basis I have* and NOTHING ELSE.  It validates the
# header and the prerequisite list and never reads the packfile -- which is
# 100% of the payload.  Measured on a real 429,265-byte bundle truncated to
# 140,000: `git bundle verify` prints the identical ref listing, says `is
# okay`, and exits 0, while the fetch that would recover it dies with `error:
# index-pack died` / `fatal: early EOF`.  A backup that verifies and cannot be
# read is the same shape as `objcopy` writing nothing and exiting 0, as a
# "clean rebuild is byte-identical" check where the rebuild never happened, and
# as a script that printed success without writing.
#
# So this performs the recovery instead of certifying it, and the three clauses
# below are each load-bearing and each was measured, not reasoned:
#
#   A FRESH REPOSITORY PER RUN.  Reusing one scratch repo and testing a good
#   bundle first leaves every object in the store, and a TORN bundle then
#   fetches rc=0, reports all 39 commits and ARCHIVES CLEANLY -- `FETCH_HEAD`
#   resolves against its predecessor's objects.  It defeats the strong test and
#   not merely the weak one, so this is the whole check and not hygiene.  It is
#   CLAUDE.md's "a harness that diffs an output file it did not first delete
#   keeps passing on the previous run's file", in a git object store.
#
#   SEED FROM THE REMOTE-TRACKING REF, never from a local `main`.  A local main
#   that is ahead of the remote already contains the bundle's commits, and then
#   every bundle passes for the wrong reason -- including a torn one.
#
#   `git archive` AND NOT `git rev-list`.  rev-list walks COMMITS, so a pack
#   missing only trees and blobs counts exactly like a whole one.  archive has
#   to read every tree and blob reachable from the tip.
#
# The cheap prerequisite check is kept and run first, because it is the only
# thing that catches the BASIS moving when a bundle is refreshed -- but it is
# not sufficient and is not described as if it were.
#
# Nothing here is part of the build.  tools/gocmp/ is named by no makefile and
# no phase program, so it enters no implementation key.
set -eu

f=${1:?usage: bundlecheck.sh <bundle> [basis-repo]}
# THE BASIS IS MADE ABSOLUTE HERE, and the default is why.  It is handed to a
# `git -C "$s/r" fetch`, which changes directory FIRST, so a relative `.`
# resolves to the scratch repository -- which has no `refs/remotes/origin/main`
# and never will.  Measured: every case, good and torn and empty alike, died
# with `fatal: couldn't find remote ref refs/remotes/origin/main` at rc=128,
# before the recovery it exists to perform, and git's message names the ref and
# not the path.  It fails loudly rather than passing, so it is not one of the
# four -- it is the other shape, a relative path handed to a command that
# changes directory.
basis=$(cd "${2:-.}" && pwd)
[ -f "$f" ] || { echo "bundlecheck: $f is not a file" >&2; exit 1; }
# AND SO IS THE BUNDLE, for the same reason and with a worse symptom.  `$f` is
# handed to the same `git -C "$s/r" fetch`, so a relative path resolves inside
# the scratch repository: the REAL bundle then fails with `'…' does not appear
# to be a git repository`, which is a plausible message and a wrong verdict.
# The torn and empty cases still fail, for the right reasons and by accident, so
# a run over all three reads as two right out of three with the one that matters
# inverted.
f=$(cd "$(dirname "$f")" && pwd)/$(basename "$f")

s=$(mktemp -d)
trap 'rm -rf "$s"' EXIT
rc=0

printf '  bundle       %s, %s bytes\n' "$f" "$(stat -c%s "$f")"

# --- 1. the cheap check: is every prerequisite reachable from the remote? ----
# QUOTE THIS ENTIRE OR NOT AT ALL.  `git bundle verify` prints the bundle's own
# HEAD ABOVE the prerequisite list, so a grep over the whole output tests the
# NEW WORK for reachability from the remote -- which it is not, by construction
# -- and fails on a correct bundle.  The sed is what confines it to the list.
prereqs=$(git bundle verify "$f" 2>/dev/null | sed -n '/requires these/,$p' |
          grep -oE '^[0-9a-f]{40}' || true)
if [ -z "$prereqs" ]; then
    # The second line is SINGLE-quoted: backticks inside a double-quoted
    # string are command substitution, and this line RAN the verify with no
    # argument and printed its usage into the middle of the diagnostic.
    # Measured on the empty-bundle case -- a message about a check that did
    # nothing, which did something instead.
    echo "  bundle       no prerequisites listed -- either the bundle is complete in"
    echo '               itself, or `git bundle verify` failed and this test is vacuous'
fi
for r in $prereqs; do
    if git -C "$basis" merge-base --is-ancestor "$r" origin/main 2>/dev/null; then
        printf '  prereq       %s reachable from origin/main\n' "$(echo "$r" | cut -c1-12)"
    else
        printf '  prereq       %s NOT REACHABLE from origin/main -- nobody with a clone\n' \
            "$(echo "$r" | cut -c1-12)"
        echo "               of the remote can apply this bundle"
        rc=1
    fi
done

# --- 2. the real check: perform the recovery ---------------------------------
git init -q "$s/r"
if ! git -C "$s/r" fetch -q "$basis" refs/remotes/origin/main:refs/heads/base 2>/dev/null; then
    echo "  basis        $basis has no refs/remotes/origin/main, so there is no basis to"
    echo "               seed from and this test would be vacuous" >&2
    exit 2
fi
printf '  basis        %s, from the remote-tracking ref and not from a local main\n' \
    "$(git -C "$s/r" rev-parse --short base)"

if ! out=$(git -C "$s/r" fetch "$f" HEAD 2>&1); then
    echo "  recover      THE FETCH FAILED -- this bundle cannot be applied, whatever"
    echo "               \`git bundle verify\` says about it:"
    echo "$out" | grep -iE 'error|fatal' | head -3 | sed 's/^/               /'
    exit 1
fi
if ! git -C "$s/r" archive FETCH_HEAD > /dev/null 2>&1; then
    echo "  recover      the fetch succeeded and \`git archive\` cannot read the tip's"
    echo "               trees and blobs, so the pack is incomplete in exactly the way"
    echo "               a commit count would not show"
    exit 1
fi
if ! git -C "$s/r" fsck --no-dangling > /dev/null 2>&1; then
    echo "  recover      the object graph does not fsck"
    exit 1
fi
printf '  recover      %s commits, archive ok, fsck ok -- RECOVERED, in a repository\n' \
    "$(git -C "$s/r" rev-list --count base..FETCH_HEAD)"
echo "               seeded with nothing but the basis"
exit "$rc"
