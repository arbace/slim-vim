#!/bin/sh
# Whim phase 22, the check -- the working directory is where it started.
# See pipes/whim22-edit.sh, and WHIM-GOAL.md.
#
# Usage: pipes/whim22-check.sh <work-dir> <state-dir>      (run from the repository root)
#
# Runs after pipes/whim22-edit.sh and the sweep tools/phaserun.sh runs between
# them, and reads nothing from the edit's shell -- only the work tree and the state
# directory, as tools/phaserun.sh describes.
set -eu

work=${1:?usage: whim22-check.sh <work-dir> <state-dir>}
state=${2:?usage: whim22-check.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"
before_lines=$(cat "$state/input-lines")

# Matched as CALLS, not as words: `[CMD_chdir]` is a retired command row that
# stays, and this phase's own comment says "chdir'd".
for g in 'mch_chdir(' 'chdir(' 'fchdir(' 'win_fix_current_dir(' \
         '\bglobaldir\b' '\bstart_dir\b'; do
    n=$(grep -c -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  cwd          $g still has $n mentions after the sweep"
        grep -nw -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
# And the one that stays, asked exactly once.
n=$(grep -c 'getcwd((char \*)' "$f" || true)
if [ "$n" != 1 ]; then
    echo "  cwd          getcwd is called $n times, expected exactly 1"
    exit 1
fi
echo "  cwd          nothing moves the process; getcwd is asked once"


tools/phasecheck.sh "$work" "$f" "$state/symbols"

for g in chdir fchdir; do
    if grep -qx -- "$g" .cache/symbols/last/undefined; then
        echo "  symbols      $g is still undefined in the object"
        exit 1
    fi
done
echo "  symbols      chdir and fchdir are gone from nm -u"

tools/phasebuild.sh "$work" "$before_lines"

# A relative name with a directory in it must still open, write and read back.
# That is the path mch_FullName used to chdir through, and no harness walks it:
# every harness edits a file in the directory it is standing in.
rel=$(cd "$work" && rm -rf .reltest && mkdir -p .reltest/sub && cd .reltest \
      && printf 'one\ntwo\n' > sub/f.txt \
      && ../whim-vim -e -s -c 'normal Gothree' -c 'wq' sub/f.txt </dev/null >/dev/null 2>&1
      cd sub && ../../whim-vim -e -s -c '%s/two/2/' -c 'wq' ../sub/f.txt </dev/null >/dev/null 2>&1
      tr '\n' ' ' < f.txt)
rm -rf "$work/.reltest"
if [ "$rel" != "one 2 three " ]; then
    echo "  relative     a relative path gave '$rel', expected 'one 2 three '"
    exit 1
fi
echo "  relative     a relative path with a directory in it opens and writes"
