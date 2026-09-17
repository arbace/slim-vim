#!/bin/sh
# Whim phase 61, the check -- no window title.
# See pipes/whim61-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim61-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim61-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim61-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim61-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in p_title p_titlelen p_titleold p_titlestring p_icon p_iconstring maketitle resettitle mch_settitle mch_restore_title \
         set_title_defaults need_maketitle lasttitle lasticon oldtitle oldicon term_settitle term_push_title term_pop_title; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  notitle      $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  notitle      nothing sets, restores, pushes or pops the terminal's title"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
(cd "$d" && HOME="$d" ./vim -e -s '+set sw=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  notitle      the control :set sw=3 failed"; exit 1; }
for o in title titlelen titleold titlestring icon iconstring; do
    if (cd "$d" && HOME="$d" ./vim -e -s "+set $o?" '+q!' </dev/null >/dev/null 2>&1); then
        echo "  notitle      :set $o? was accepted"; exit 1
    fi
done
echo "  notitle      :set sw works; the six title and icon options are unknown"
