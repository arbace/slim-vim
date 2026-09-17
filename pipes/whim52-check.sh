#!/bin/sh
# Whim phase 52, the check -- UTF-8 is not a question.
# See pipes/whim52-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim52-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim52-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim52-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim52-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in enc_utf8 has_mbyte enc_dbcs enc_unicode enc_latin1like __T__ __F__ __Z__; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  utf8only     $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  utf8only     no encoding flag is asked, and $(grep -cE '\bdbcs_[a-z_0-9]+\(' "$f" || true) DBCS call sites are left"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# Multibyte editing, by the bytes: gUU over a-grave e-acute, and x on a
# three-byte character, against what they must produce.
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
printf '\303\240\303\251\n' > "$d/u.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1normal! gUU' '+wq' u.txt </dev/null >/dev/null 2>&1) || true
[ "$(od -An -tx1 "$d/u.txt" | tr -d ' \n')" = c380c3890a ] || { echo "  utf8only     gUU over a-grave e-acute gave $(od -An -tx1 "$d/u.txt")"; exit 1; }
printf 'a\346\227\245b\n' > "$d/x.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1normal! 0lx' '+wq' x.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/x.txt")" = ab ] || { echo "  utf8only     x on a three-byte character left '$(cat "$d/x.txt")'"; exit 1; }
echo "  utf8only     gUU and x work on multibyte characters"
