#!/bin/sh
# Whim phase 51, the check -- a byte that is not UTF-8 is kept as it is.
# See pipes/whim51-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim51-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim51-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim51-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim51-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in get_bad_opt bad_char_behavior b_bad_char BAD_REPLACE; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  keepbytes    $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  keepbytes    nothing replaces, drops or chooses what to do with an invalid byte"

tools/phasecheck.sh "$work" "$f" "$state/symbols"

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# The control: a valid UTF-8 edit still works.
printf 'caf\303\251\n' > "$d/u.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+s/\%u00e9/E/' '+wq' u.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/u.txt")" = cafE ] || { echo "  keepbytes    the control failed: a UTF-8 edit gave '$(cat "$d/u.txt")'"; exit 1; }

# An invalid byte comes back as it went in, and the buffer is not read-only.
printf 'ok\n\377 bad\n' > "$d/ill.txt"
# +1s, not +s: Ex mode starts on the last line, and an :s that does not match
# there is an error that stops the commands after it -- including the :wq.
(cd "$d" && HOME="$d" ./vim -e -s '+1s/ok/OK/' '+wq' ill.txt </dev/null >/dev/null 2>&1) || true
if [ "$(od -An -c "$d/ill.txt" | tr -d ' \n')" != 'OK\n377bad\n' ]; then
    echo "  keepbytes    an invalid byte was not written back unchanged: $(od -An -c "$d/ill.txt" | tr -s ' ')"; exit 1
fi
ro=$(cd "$d" && HOME="$d" ./vim -e -s '+set ro?' '+q!' ill.txt </dev/null 2>&1 | tr -d ' \n')
[ "$ro" = noreadonly ] || { echo "  keepbytes    reading an invalid byte made the buffer '$ro'"; exit 1; }
if (cd "$d" && HOME="$d" ./vim -e -s '+e ++bad=keep ill.txt' '+q!' </dev/null >/dev/null 2>&1); then
    echo "  keepbytes    ++bad=keep was accepted"; exit 1
fi
echo "  keepbytes    an invalid byte is written back unchanged, the buffer stays writable, ++bad is refused"
