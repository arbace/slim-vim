#!/bin/sh
# Whim phase 53, the check -- no conversion layer, no 'encoding'.
# See pipes/whim53-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim53-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim53-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim53-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim53-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in need_conversion get_fio_flags check_for_bom next_fenc set_forced_fenc enc_canonize \
         force_enc p_enc iconv_fd ucs2bytes mb_ptr2len mb_head_off mb_ptr2char latin_ptr2len \
         dbcs_head_off dbcs_ptr2len get_encoding_name get_bad_name get_fileformat_name \
         input_conv output_conv convert_setup string_convert convert_input_safe p_menc b_p_menc did_set_encoding; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  noconv       $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  noconv       no conversion, no 'encoding', no mb_* pointer, no DBCS path"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
(cd "$d" && HOME="$d" ./vim -e -s '+set ts=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  noconv       the control :set ts=3 failed"; exit 1; }
if (cd "$d" && HOME="$d" ./vim -e -s '+set enc?' '+q!' </dev/null >/dev/null 2>&1); then
    echo "  noconv       :set enc? was accepted"; exit 1
fi
if (cd "$d" && HOME="$d" ./vim -e -s '+set menc?' '+q!' </dev/null >/dev/null 2>&1); then
    echo "  noconv       :set menc? was accepted"; exit 1
fi
printf 'x\n' > "$d/e.txt"
if (cd "$d" && HOME="$d" ./vim -e -s '+e ++enc=latin1 e.txt' '+q!' </dev/null >/dev/null 2>&1); then
    echo "  noconv       ++enc was accepted"; exit 1
fi
printf '\303\240\303\251\n' > "$d/u.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1normal! gUU' '+wq' u.txt </dev/null >/dev/null 2>&1) || true
[ "$(od -An -tx1 "$d/u.txt" | tr -d ' \n')" = c380c3890a ] || { echo "  noconv       gUU over a-grave e-acute gave $(od -An -tx1 "$d/u.txt")"; exit 1; }
printf 'ok\n\377 bad\n' > "$d/ill.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1s/ok/OK/' '+wq' ill.txt </dev/null >/dev/null 2>&1) || true
[ "$(od -An -c "$d/ill.txt" | tr -d ' \n')" = 'OK\n377bad\n' ] || { echo "  noconv       an invalid byte was not kept: $(od -An -c "$d/ill.txt" | tr -s ' ')"; exit 1; }
echo "  noconv       :set enc, :set menc and ++enc refused; UTF-8 edits and a kept invalid byte unchanged"
