#!/bin/sh
# Whim phase 73, the check -- one frame.
# See pipes/whim73-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim73-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim73-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim73-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim73-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# The tree is gone, and so is everything that only existed to walk it.
for g in fr_parent fr_next fr_prev fr_child frame_fixed_height frame_fixed_width \
         FR_ROW FR_COL; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  oneframe     $g still has $n mentions"; exit 1; }
done
# The one frame and its SIZE stay -- they are live layout state.
for g in frame_T topframe fr_width fr_height fr_win fr_layout FR_LEAF new_frame \
         win_comp_pos frame_comp_pos frame_minheight win_new_height; do
    grep -qE "\\b$g\\b" "$f" || { echo "  oneframe     $g went -- the one frame still needs it"; exit 1; }
done
# frame_minheight must keep its arithmetic: min_rows and the :set cmdheight clamp
# both depend on the number, so a constant return would move what the option accepts.
awk '/^frame_minheight\(/,/^\}$/' "$f" | grep -qE '\bp_wmh\b' || { echo "  oneframe     frame_minheight lost its arithmetic"; exit 1; }
awk '/^frame_minheight\(/,/^\}$/' "$f" | grep -qE '\bp_wh\b'  || { echo "  oneframe     frame_minheight lost its arithmetic"; exit 1; }
echo "  oneframe     one frame; its width, height and the minima kept"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# LOAD FIRST.
printf 'a\nb\nc\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+$' '+s/^/LAST /' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'a|b|LAST c|' ] || { echo "  oneframe     the file did not load: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }

printf 'one\ntwo\nthree\n' > "$d/e.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+2' '+normal! dd' '+wq' e.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/e.txt")" = 'one|three|' ] || { echo "  oneframe     editing broke: '$(tr '\n' '|' < "$d/e.txt")'"; exit 1; }

printf 'h1\n' > "$d/h1.txt"; printf 'h2\n' > "$d/h2.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+e h2.txt' '+normal! iE' '+wq' h1.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/h1.txt")" = 'h1' ] || { echo "  oneframe     :e wrote over the first file: $(cat "$d/h1.txt")"; exit 1; }
[ "$(cat "$d/h2.txt")" = 'Eh2' ] || { echo "  oneframe     :e did not load the second file: $(cat "$d/h2.txt")"; exit 1; }

# no bang: normal! suppresses mappings by definition.  Calibrated in phase 71.
printf 'x\n' > "$d/m.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+map <buffer> Q A!' '+normal Q' '+wq' m.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/m.txt")" = 'x!' ] || { echo "  oneframe     a buffer-local mapping stopped working: $(cat "$d/m.txt")"; exit 1; }

# the scroll path, which reads topframe->fr_width in win_do_lines
printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n' > "$d/s.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+5' '+normal! O-ins' '+wq' s.txt </dev/null >/dev/null 2>&1) || true
[ "$(sed -n 5p "$d/s.txt")" = '-ins' ] || { echo "  oneframe     inserting a line broke the scroll path: $(sed -n 5p "$d/s.txt")"; exit 1; }

# :set cmdheight goes through did_set_cmdheight -> command_height -> frame_add_height,
# which this phase rewrote, and its clamp reads frame_minheight.  A write that
# completes afterwards is the evidence that the resize did not wedge the layout.
printf 'c1\nc2\n' > "$d/c.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+set cmdheight=2' '+1' '+normal! A-ch' '+wq' c.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/c.txt")" = 'c1-ch|c2|' ] || { echo "  oneframe     :set cmdheight broke the layout: '$(tr '\n' '|' < "$d/c.txt")'"; exit 1; }

# 'laststatus' drives last_status -> last_status_rec, the other rewritten body
printf 'l1\nl2\n' > "$d/l.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+set laststatus=2' '+1' '+normal! A-ls' '+wq' l.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/l.txt")" = 'l1-ls|l2|' ] || { echo "  oneframe     'laststatus' broke the layout: '$(tr '\n' '|' < "$d/l.txt")'"; exit 1; }
echo "  oneframe     loads, edits, :e switches, mappings fire, cmdheight and laststatus resize"
