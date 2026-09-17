#!/bin/sh
# Whim phase 59, the check -- no command-line completion.
# See pipes/whim59-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim59-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim59-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim59-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim59-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# ExpandOne's only caller must be expand_filename() once the sweep has taken the
# dead ones -- nextwild(), showmatches() and the rest -- or a mode folded above is
# still asked for.  Before the sweep they are all still there, which a first
# version of this check found out by failing.
callers=$(grep -cE '\bExpandOne\(' "$f" || true)
[ "$callers" = 3 ] || { echo "  nocompletion ExpandOne is named $callers times, expected 3 (prototype, definition, expand_filename)"; grep -nE '\bExpandOne\(' "$f" | cut -c1-120; exit 1; }


for g in p_wc p_wcm p_wim p_wop p_wig p_wic wim_flags nextwild showmatches cmdline_wildchar_complete set_expand_context \
         set_one_cmd_context ExpandSettings ExpandMappings ExpandBufnames expand_argopt get_next_or_prev_match \
         find_longest_match did_wild_list check_opt_wim; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  nocompletion $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  nocompletion no completion key, context, match list or wild* option is left"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
(cd "$d" && HOME="$d" ./vim -e -s '+set sw=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  nocompletion the control :set sw=3 failed"; exit 1; }
for o in wildchar wildcharm wildmode wildoptions wildignore wildignorecase; do
    if (cd "$d" && HOME="$d" ./vim -e -s "+set $o?" '+q!' </dev/null >/dev/null 2>&1); then
        echo "  nocompletion :set $o? was accepted"; exit 1
    fi
done
# :e still takes a file name.  NOT a wildcard: `:e onlyo*` already failed to
# expand in the previous phase's binary -- it wrote a file named `onlyo*` -- so a
# probe that demanded expansion checked something this phase never had.
printf 'x\n' > "$d/onlyone.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+e onlyone.txt' '+1s/x/y/' '+w' '+q!' </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/onlyone.txt")" = y ] || { echo "  nocompletion :e onlyone.txt did not edit it: '$(cat "$d/onlyone.txt")'"; exit 1; }
echo "  nocompletion :set sw works; the wild* options are unknown; :e still edits a named file"
