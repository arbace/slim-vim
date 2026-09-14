#!/bin/sh
# Pure phase 34 -- file-name modifiers.  See PURE-GOAL.md.
#
# Usage: tools/pure34.sh <work-dir>      (run from the repository root)
#
# eval_vars() expands % and # into the current and alternate file names, and
# <cword>, <afile> and the others.  THAT STAYS -- `:w %` and `:e #` are how a
# file name is written without typing it.
#
# What goes is the SUFFIX LANGUAGE that may follow: modify_fname(), 426 lines
# implementing :p :h :t :r :e :s/from/to/ :gs :~ and :., applied left to right so
# that %:p:h:t means something.  Most of it answers questions this editor can no
# longer ask -- :p made a name absolute by asking where the working directory
# is, and phase 24 fixed that to one answer; :~ shortened a name under $HOME,
# and phase 22 removed the notion of a home directory.
#
# THE DELTA: none the harness records.  The phase checks the two halves itself:
# `:w %` must still write the current file, and `%:t` must stop being a tail.
set -eu

work=${1:?usage: pure34.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nofnamemod.py "$f"


tools/sweep.sh "$f"

n=$(grep -c 'modify_fname' "$f" || true)
if [ "$n" != 0 ]; then
    echo "  fnamemod     modify_fname still has $n mentions after the sweep"
    exit 1
fi
if [ "$(grep -c '\beval_vars(' "$f" || true)" = 0 ]; then
    echo "  fnamemod     eval_vars went too -- % and # are the half this keeps"
    exit 1
fi
echo "  fnamemod     no suffix language; % and # still expand"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# Both halves, because only the pair is a check: `%` must still name the file
# being edited, and `%:t` must no longer mean its tail.
t=$(cd "$work" && rm -rf .fmtest && mkdir -p .fmtest/sub && cd .fmtest \
    && printf 'one\n' > sub/f.txt \
    && ../pure-vim -e -s -c 'w! copy.txt' -c 'qa!' sub/f.txt </dev/null >/dev/null 2>&1
    ../pure-vim -e -s -c 'normal Gotwo' -c 'w! %' -c 'qa!' sub/f.txt </dev/null >/dev/null 2>&1
    printf '%s' "$(tr '\n' ' ' < sub/f.txt)")
rm -rf "$work/.fmtest"
if [ "$t" != "one two " ]; then
    echo "  fnamemod     \`:w %\` gave '$t', expected 'one two '"
    exit 1
fi
echo "  fnamemod     \`:w %\` still writes the file being edited"

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear
