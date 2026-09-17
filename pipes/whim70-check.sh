#!/bin/sh
# Whim phase 70, the check -- :e reloads in place, and there is no swap file.
# See pipes/whim70-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim70-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim70-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim70-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim70-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# fname2fnum() is FOLDED, not removed: getmark_buf_fnum() still calls it, and the
# file marks are a separate cut.  What matters is that its body can no longer make a
# buffer -- an empty shell with a live caller is not a leftover, it is the fold.
awk '/^fname2fnum\(/,/^\}$/' "$f" | grep -qE '\bbuflist_new\b' && { echo "  onebuffer    fname2fnum can still create a buffer"; exit 1; }
n=$(grep -cE -- '\bfname2fnum\b' "$f" || true)
[ "$n" = 3 ] || { echo "  onebuffer    fname2fnum has $n mentions, expected 3 (prototype, call, definition)"; exit 1; }
# buflist_new must still exist -- the FIRST buffer comes from it -- but do_ecmd may
# no longer call it, and nothing may wipe a buffer to switch to another.
awk '/^do_ecmd\(/,/^\}$/' "$f" | grep -qE '\bbuflist_new\b|\bbuflist_findnr\b' && { echo "  onebuffer    do_ecmd still reaches for another buffer"; exit 1; }
awk '/^do_ecmd\(/,/^\}$/' "$f" | grep -qE 'close_buffer\(curwin, curbuf, DOBUF_WIPE' && { echo "  onebuffer    do_ecmd still wipes the buffer it leaves"; exit 1; }
for g in buflist_new setfname open_buffer buf_freeall readfile do_ecmd; do
    grep -qE "\\b$g\\b" "$f" || { echo "  onebuffer    $g went too -- the one buffer still needs it"; exit 1; }
done
echo "  onebuffer    :edit reuses the one buffer; nothing creates or wipes another"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# LOAD FIRST.  No probe key here contains a quote, which is what made an earlier
# phase's marks probes measure nothing at all.
printf 'a\nb\nc\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+$' '+s/^/LAST /' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'a|b|LAST c|' ] || { echo "  onebuffer    the file did not load: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }

# :e still opens the other file, and the write follows it -- measured on q69.
printf 'h1\n' > "$d/h1.txt"; printf 'h2\n' > "$d/h2.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+e h2.txt' '+normal! iE' '+wq' h1.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/h1.txt")" = 'h1' ] || { echo "  onebuffer    :e wrote over the first file: $(cat "$d/h1.txt")"; exit 1; }
[ "$(cat "$d/h2.txt")" = 'Eh2' ] || { echo "  onebuffer    :e did not load the second file: $(cat "$d/h2.txt")"; exit 1; }

# editing and writing the plain case
printf 'one\ntwo\nthree\n' > "$d/e.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+2' '+normal! dd' '+wq' e.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/e.txt")" = 'one|three|' ] || { echo "  onebuffer    editing broke: '$(tr '\n' '|' < "$d/e.txt")'"; exit 1; }

# :e with no name reloads the file, discarding an unwritten change
printf 'keep\n' > "$d/r.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+normal! iX' '+e!' '+wq' r.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/r.txt")" = 'keep' ] || { echo "  onebuffer    :e! did not reload: $(cat "$d/r.txt")"; exit 1; }
echo "  onebuffer    the file loads and edits; :e opens another; :e! reloads"
