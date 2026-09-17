#!/bin/sh
# Whim phase 63, the check -- no jump list.
# See pipes/whim63-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim63-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim63-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim63-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim63-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in w_jumplist w_jumplistlen w_jumplistidx movemark cleanup_jumplist copy_jumplist free_jumplist ex_jumps ex_clearjumps; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  nojumplist   $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
grep -q 'w_pcmark' "$f" || { echo "  nojumplist   w_pcmark went too -- the '' mark was not the jump list's"; exit 1; }
grep -q 'movechangelist' "$f" || { echo "  nojumplist   movechangelist went too -- g; and g, were not the jump list's"; exit 1; }
echo "  nojumplist   no jump list is left; the '' mark and the change list are"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
if (cd "$d" && HOME="$d" ./vim -e -s '+jumps' '+q!' </dev/null >/dev/null 2>&1); then
    echo "  nojumplist   :jumps was accepted"; exit 1
fi
printf 'a\nb\nc\n' > "$d/j.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! 3G' "$(printf '+normal! \017')" '+s/^/X/' '+wq' j.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/j.txt")" = 'a|b|Xc|' ] || { echo "  nojumplist   CTRL-O moved the cursor: '$(tr '\n' '|' < "$d/j.txt")'"; exit 1; }
printf 'a\nb\nc\n' > "$d/k.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' "+normal! 3G''" '+s/^/Y/' '+wq' k.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/k.txt")" = 'Ya|b|c|' ] || { echo "  nojumplist   '' did not return to line 1: '$(tr '\n' '|' < "$d/k.txt")'"; exit 1; }
echo "  nojumplist   :jumps is refused; CTRL-O stays put; '' still jumps back"
