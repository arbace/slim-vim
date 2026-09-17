#!/bin/sh
# Whim phase 71, the check -- one buffer, structurally.
# See pipes/whim71-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim71-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim71-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim71-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim71-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The three things named b_next that are NOT the buffer list must all survive.
grep -qE '^[ \t]*buffblock_T \*b_next;' "$f" || { echo "  onebuf       buffblock_T lost its b_next -- the redo buffer is gone"; exit 1; }
for g in bh_first redobuff readbuf1 readbuf2; do
    grep -qE "\\b$g\\b" "$f" || { echo "  onebuf       $g went -- that was never the buffer list"; exit 1; }
done
# and the list itself must be gone
for g in firstbuf lastbuf buf_reuse BLN_REUSE au_pending_free_buf; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  onebuf       $g still has $n mentions"; exit 1; }
done
# DOBUF_WIPE_REUSE keeps its enum and the two tests that name it; what must be gone
# is any CALLER passing it, which is what made the wipe branch reachable.
grep -nE '\b(close_buffer|set_curbuf)\([^;]*DOBUF_WIPE_REUSE' "$f" && { echo "  onebuf       something still asks for a reusable wipe"; exit 1; }
# a buf_T may no longer point at another buf_T
awk '/^struct file_buffer$/,/^\};$/' "$f" | grep -qE 'buf_T[ \t]+\*b_(next|prev);' && { echo "  onebuf       buf_T still links to another buffer"; exit 1; }
# the one buffer still has to be MADE, and looked up by number
for g in buflist_new buflist_add buflist_findnr buf_hashtab win_alloc_firstwin; do
    grep -qE "\\b$g\\b" "$f" || { echo "  onebuf       $g went too -- the one buffer still needs it"; exit 1; }
done
# the mapping scan must still make two passes
grep -qE 'for \(bp = curbuf; ; bp = NULL\)' "$f" || { echo "  onebuf       the mapping scan no longer runs its global pass"; exit 1; }
echo "  onebuf       one buffer, structurally; the redo chain and the free list untouched"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# LOAD FIRST, as always: prove the buffer holds the file before testing anything else.
printf 'a\nb\nc\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+$' '+s/^/LAST /' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'a|b|LAST c|' ] || { echo "  onebuf       the file did not load: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }

# :e still switches files, and the write follows it (phase 70's behaviour, unchanged)
printf 'h1\n' > "$d/h1.txt"; printf 'h2\n' > "$d/h2.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+e h2.txt' '+normal! iE' '+wq' h1.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/h1.txt")" = 'h1' ] || { echo "  onebuf       :e wrote over the first file: $(cat "$d/h1.txt")"; exit 1; }
[ "$(cat "$d/h2.txt")" = 'Eh2' ] || { echo "  onebuf       :e did not load the second file: $(cat "$d/h2.txt")"; exit 1; }

# plain editing
printf 'one\ntwo\nthree\n' > "$d/e.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+2' '+normal! dd' '+wq' e.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/e.txt")" = 'one|three|' ] || { echo "  onebuf       editing broke: '$(tr '\n' '|' < "$d/e.txt")'"; exit 1; }

# BUFFER-LOCAL MAPPINGS still work.  NOTE THE MISSING BANG, and do not put it back:
# `normal!` suppresses mappings by definition, so a mapping probe written with it
# cannot fire on ANY build and measures nothing.  Calibrated against q70, which gives
# x with the bang and x! without it -- the same answer this phase gives, which is how
# the invalid probe was caught.  It is the <LeftMouse> mistake in another costume.
printf 'x\n' > "$d/m.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+map <buffer> Q A!' '+normal Q' '+wq' m.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/m.txt")" = 'x!' ] || { echo "  onebuf       a buffer-local mapping stopped working: $(cat "$d/m.txt")"; exit 1; }

# a global mapping too, which is the second pass of check_map_keycodes' walk
printf 'y\n' > "$d/g.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+map Z A?' '+normal Z' '+wq' g.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/g.txt")" = 'y?' ] || { echo "  onebuf       a global mapping stopped working: $(cat "$d/g.txt")"; exit 1; }

# '#' has no alternate file to name, and must say so rather than crash
printf 'z\n' > "$d/alt.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+normal! A1' '+wq' alt.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/alt.txt")" = 'z1' ] || { echo "  onebuf       editing after the alternate-file cut broke: $(cat "$d/alt.txt")"; exit 1; }
echo "  onebuf       loads, edits, :e switches, and both mapping passes still fire"
