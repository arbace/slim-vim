#!/bin/sh
# Whim phase 21, the check -- there is nothing to recover, and the memfile is memory.
# See pipes/whim21-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim21-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim21-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim21-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim21-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

for g in mf_fd mf_fname mf_ffname mf_write mf_read mf_release total_mem_used p_mmt p_dir \
         mch_total_mem mch_get_host_name; do
    n=$(grep -cw -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  memfile      $g still has $n mentions after the sweep"
        grep -nw -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  memfile      no descriptor, no eviction, no memory budget"


tools/phasecheck.sh "$work" "$f" "$state/symbols"
for g in getpwuid localtime_r strftime; do
    if grep -qx -- "$g" .cache/symbols/last/undefined; then
        echo "  symbols      $g is still undefined in the object"
        exit 1
    fi
done
echo "  symbols      getpwuid is gone -- the last of the five password symbols"
for g in sysinfo getrlimit uname; do
    if grep -qx -- "$g" .cache/symbols/last/undefined; then
        echo "  symbols      $g is still undefined in the object"
        exit 1
    fi
done
echo "  symbols      sysinfo, getrlimit and uname are gone from nm -u"

tools/phasebuild.sh "$work" "$before_lines"

# The check this phase owes phase 11: the crash it is fixing.  A harness that
# does not write over an existing file under another name with `!` cannot see
# it, and none of them does -- which is how it survived twelve phases.
ov=$(cd "$work" && rm -rf .ovtest && mkdir .ovtest && cd .ovtest \
     && printf 'one\n' > a.txt && printf 'two\n' > b.txt \
     && ../whim-vim -e -s -c 'w! b.txt' -c 'qa!' a.txt </dev/null >/dev/null 2>&1
     printf '%s' "$?:$(cat b.txt 2>/dev/null)")
rm -rf "$work/.ovtest"
if [ "$ov" != "0:one" ]; then
    echo "  overwrite    :w! over an existing other file gave $ov, expected 0:one"
    exit 1
fi
echo "  overwrite    :w! over an existing other file writes it"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
