#!/bin/sh
# Whim phase 58, the check -- no language mappings.
# See pipes/whim58-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim58-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim58-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim58-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim58-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in b_p_iminsert b_p_imsearch p_iminsert p_imsearch B_IMODE_NONE B_IMODE_LMAP B_IMODE_LAST MODE_LANGMAP \
         ins_ctrl_hat cmdline_toggle_langmap set_iminsert_global set_imsearch_global did_set_iminsert did_set_imsearch \
         get_keymap_str b_im_ptr langmap_active; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  nolangmap    $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  nolangmap    no language-mapping mode, toggle or option is left"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
(cd "$d" && HOME="$d" ./vim -e -s '+set sw=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  nolangmap    the control :set sw=3 failed"; exit 1; }
for o in iminsert imsearch; do
    if (cd "$d" && HOME="$d" ./vim -e -s "+set $o?" '+q!' </dev/null >/dev/null 2>&1); then
        echo "  nolangmap    :set $o? was accepted"; exit 1
    fi
done
if (cd "$d" && HOME="$d" ./vim -e -s '+lmap a b' '+q!' </dev/null >/dev/null 2>&1); then
    echo "  nolangmap    :lmap was accepted"; exit 1
fi
printf 'x\n' > "$d/h.txt"
(cd "$d" && HOME="$d" ./vim -e -s "$(printf '+1normal! Ia\036b')" '+wq' h.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/h.txt")" = abx ] || { echo "  nolangmap    CTRL-^ in Insert mode left '$(cat "$d/h.txt")'"; exit 1; }
echo "  nolangmap    :set sw works; iminsert, imsearch and :lmap are unknown; CTRL-^ inserts nothing"
