#!/bin/sh
# Whim phase 67, the check -- no mouse, no spell plumbing, no write-only flags.
# See pipes/whim67-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim67-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim67-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim67-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim67-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in is_mouse_key dragwin held_button mouse_row mouse_col old_mouse_row old_mouse_col \
         reset_dragwin reset_held_button spellvars_T spv_has_spell \
         did_check_timestamps did_emsg_syntax typebuf_was_empty in_mch_delay frame_locked \
         swap_exists_did_quit did_swapwrite_msg autocmd_nested oldtitle_outdated deadly_signal \
         mr_patternlen was_safe state_no_longer_safe mouse_index_found looks_like_mouse_start; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  nomouse      $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
n=$(grep -cE '\(char_u \*\)\("\w*(Mouse|Drag|Release|Wheel)\w*"\)' "$f" || true)
[ "$n" = 0 ] || { echo "  nomouse      $n mouse key names left in key_names_table"; grep -nE '\(char_u \*\)\("\w*(Mouse|Drag|Release|Wheel)\w*"\)' "$f" | head -3 | cut -c1-110; exit 1; }
# vim_ignored stays: it swallows warn_unused_result, and removing it adds warnings.
grep -q '\bvim_ignored\b' "$f" || { echo "  nomouse      vim_ignored went -- warn_unused_result has nothing to assign to"; exit 1; }
# and the nv_cmds rows stay, because that table's index is a permutation of its rows
n=$(awk '/nv_cmds\[\] =/,/^\};/' "$f" | grep -cE 'KE_(MOUSE|LEFT|MIDDLE|RIGHT|X1|X2)|SCROLLBAR|TABLINE|TABMENU')
[ "$n" = 26 ] || { echo "  nomouse      $n mouse rows left in nv_cmds, expected 26 kept at nv_error"; exit 1; }
echo "  nomouse      no mouse, spell plumbing or write-only flag is left; the nv_cmds rows are"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
printf 'alpha\nbeta\ngamma\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+2' '+normal! dd' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'alpha|gamma|' ] || { echo "  nomouse      editing broke: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }
# NOT a probe for <LeftMouse>: an unrecognised <...> is taken as a LITERAL string
# rather than refused, so `:map <LeftMouse> x` is accepted whether the name exists
# or not -- measured on the q66 binary and on this one, along with <Foo> and
# <ZZnotakey>.  A probe that cannot fail proves nothing, so the evidence that the
# names are gone is the grep above, and what is checked here is that mapping a key
# name that DOES exist still works.
(cd "$d" && HOME="$d" ./vim -e -s '+map <Home> x' '+q!' </dev/null >/dev/null 2>&1) || { echo "  nomouse      mapping a real key name broke"; exit 1; }
echo "  nomouse      editing works; a real key name still maps"
