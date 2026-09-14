#!/bin/sh
# Whim phase 22 -- the working directory is where it started.  See WHIM-GOAL.md.
#
# Usage: tools/whim22.sh <work-dir>      (run from the repository root)
#
# :cd, :lcd and :tcd are ex_ni, :! no longer forks, and nothing else in this
# editor moves the process.  So the directory it starts in is the one it dies
# in, and three pieces of machinery that exist because that was not true stop
# being needed:
#
#   * mch_FullName() chdir'd into the leading directory of a relative name,
#     asked getcwd() where that landed, and chdir'd back -- via fchdir() on a
#     descriptor it held open, falling back to chdir().  That is what resolved
#     `..` and a symlinked directory on the way to a full name.  FCHDIR.
#   * win_fix_current_dir() restores a window's or tab's local directory, and
#     runs only when w_localdir, tp_localdir or globaldir is set.  The first two
#     come only from :lcd and :tcd; globaldir is assigned only inside this
#     function.  Unreachable.
#   * edit_buffers() takes a cwd to return to between -o windows, and is passed
#     start_dir -- `static char_u *start_dir = NULL;`, which nothing assigns.
#     CHDIR, once mch_chdir() has no callers left.
#
# WHAT IT COSTS, which is why this is a phase and not a cleanup: a full name is
# now the working directory with the name appended, so `../x/y` becomes
# /cwd/../x/y rather than /real/x/y.  It opens the same file; what it loses is
# that two spellings of one path no longer compare equal, so `:e ../x/y` and
# `:e /real/x/y` are two buffers rather than one.
#
# getcwd STAYS, and is now asked once.  shorten_fnames() shortens every
# displayed name against it and mch_FullName() is how a relative name becomes
# absolute at all -- dropping it would mean b_ffname could not be a full path,
# which is a capability cut rather than plumbing.  Since nothing can move the
# process, the answer cannot change: it is read into a static on the first call.
#
# THE DELTA: none the harness records.
set -eu

work=${1:?usage: whim22.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nochdir.py "$f"


tools/sweep.sh "$f"

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


tools/phasecheck.sh "$work" "$f" .cache/symbols/before

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

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
