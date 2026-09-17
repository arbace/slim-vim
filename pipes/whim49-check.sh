#!/bin/sh
# Whim phase 49, the check -- one set of options.
# See pipes/whim49-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim49-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim49-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim49-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim49-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in do_modelines chk_modeline p_mls p_mle p_mlstr p_ml p_ml_nobin b_p_ml b_p_ml_nobin \
         modeline_whitelist is_modeline_whitelisted; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  optset       $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  optset       no modeline, and nothing that set one copy of an option"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

# :set opt< must be refused, and an ordinary :set still taken.
out=$(cd "$work" && ./whim-vim -e -s '+set ts=3' '+q!' </dev/null 2>&1) && rc=0 || rc=$?
[ "$rc" = 0 ] || { echo "  optset       the control failed: :set ts=3 exits $rc: $out"; exit 1; }
out=$(cd "$work" && ./whim-vim -e -s '+set ts<' '+q!' </dev/null 2>&1) && rc=0 || rc=$?
[ "$rc" = 1 ] || { echo "  optset       :set ts< exits $rc, expected 1: $out"; exit 1; }

# A modeline must no longer set anything.  'modelinestrict' let a modeline set
# only whitelisted options, and 'fileformat' was not one of them, so a first
# version of this check that used ff=dos passed against binaries that still read
# modelines.  'shiftwidth' is on the whitelist and shows in the bytes: >> on a
# file whose modeline says sw=2 indents by two if the modeline was read, and by
# the compiled-in four if not.
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
printf 'one\n# vim: set sw=2:\n' > "$d/m.txt"
(cd "$d" && HOME="$d" "$OLDPWD/$work/whim-vim" -e -s '+1normal! >>' '+w' '+q!' m.txt </dev/null >/dev/null 2>&1) || true
if [ "$(head -1 "$d/m.txt")" != "    one" ]; then
    echo "  optset       a modeline set 'shiftwidth': the first line is '$(head -1 "$d/m.txt")'"
    exit 1
fi
echo "  optset       :set ts< is refused, and a modeline sets nothing"
