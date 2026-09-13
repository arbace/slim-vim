#!/bin/sh
# Pure phase 24 -- nothing is read from the environment.  See PURE-GOAL.md.
#
# Usage: tools/pure24.sh <work-dir>      (run from the repository root)
#
# The third and last of the standalone phases: 20 stopped reading configuration
# files, 23 stopped believing in a home directory, and this one removes the
# environment itself.  After it, no answer this editor gives depends on how it
# was invoked.
#
# vim_getenv() is where nearly all of it went through, and it had already been
# half dead: phase 1 folded its `vimruntime` flag to FALSE, so
# vim_getenv("VIMRUNTIME") returned NULL unconditionally, and "VIM" was the only
# name left that could reach the fallback chain -- which nothing asks for.  So
# the function CAN ONLY EVER ANSWER "not set", and each caller collapses to the
# branch it was already taking: $VAR in a file name, $PATH for command-name
# completion, $SHELL, $CDPATH, $TMPDIR, $VIM_POSIX, $COLORFGBG, $TZ, and the
# $VIM/$VIMRUNTIME/$MYVIMDIR that vimrc_found() used to publish -- itself
# unreachable since phase 20, every do_source() call passing DOSO_NONE.
#
# THIS IS THE CHECK, and it is why the phase exists as its own: getenv, setenv,
# unsetenv and environ leave `nm -u`.  Grepping the source is not enough -- the
# sweep is what removes vim_getenv, and asking before it runs gets the wrong
# answer, which cost this pipeline four phases to learn.
#
# WHAT STAYS: vim_localtime() still calls localtime_r(), and musl reads $TZ
# inside it.  The rule is that THIS SOURCE asks the environment nothing; showing
# a file's timestamp in UTC would be a different decision.
#
# THE DELTA: none the harness records.  `:e $HOME/x` opens a file called
# `$HOME/x`, and `:set shell?` says sh whatever the shell was.
set -eu

work=${1:?usage: pure24.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut the entry points -------------------------------------------------
python3 tools/nogetenv.py "$f"


tools/sweep.sh "$f"

# The post-condition, asked AFTER the sweep for the reason above.
for g in getenv setenv unsetenv environ vim_getenv; do
    n=$(grep -cw -- "$g" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  environment  $g still has $n mentions after the sweep"
        grep -nw -- "$g" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  environment  nothing in the source asks the environment anything"

tools/canon.sh "$f"



tools/phasecheck.sh "$work" "$f" .cache/symbols/before

# And the same question of the object, which is the one that cannot be argued
# with: a libc call this source no longer writes could still arrive through a
# macro or an inline.
for g in getenv setenv unsetenv environ; do
    if grep -qx -- "$g" .cache/symbols/last/undefined; then
        echo "  symbols      $g is still undefined in the object"
        exit 1
    fi
done
echo "  symbols      getenv, setenv, unsetenv and environ are gone from nm -u"

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime
