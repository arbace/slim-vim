#!/bin/sh
# Pure phase 8 -- :! keeps its name and loses its process.  See PURE-GOAL.md.
#
# Usage: tools/pure10.sh <work-dir>      (run from the repository root)
#
# `:!cmd`, `:[range]!cmd`, `:r !cmd`, `:w !cmd` and `:shell` keep their names,
# their ranges and their parsing.  What goes is everything under them -- the
# fork, the exec, the pipe, the wait -- and the temporary file with them,
# because a temp file is not interface.  It exists only because a Unix shell
# needs a file to read a range out of, and there is no longer a shell.
#
# THE PLACEMENT IS THE PHASE.  do_filter() calls vim_tempname() BEFORE it
# reaches mch_call_shell(), so stubbing the shell alone leaves the whole
# temporary-directory layer alive, assembling a file for a command that will
# never run.  Measured on a scratch build before this was written: cutting at
# mch_call_shell removes 6 libc symbols; cutting at do_filter/do_shell/
# get_cmd_output removes 16.
#
# This is also the seam to keep in mind for whatever comes after pure-vim.  An
# embedded editor with no process of its own may still be given a filter by its
# host, and do_filter() and do_shell() are exactly where that would attach --
# which is a reason to leave the two of them named and reporting rather than
# retired to ex_ni.
#
# THE DELTA: filtering and shelling out report "E319: Sorry, the command is not
# available in this version" instead of running anything.  :language completion
# stops listing locales, silently, because it got them from `locale -a`.
set -eu

work=${1:?usage: pure12.sh <work-dir>}
f="$work/pure-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- cut above the temp file ----------------------------------------------
python3 tools/noshellout.py "$f"

tools/sweep.sh "$f"

tools/canon.sh "$f"



# This is the first pure phase whose point is the SYMBOL count, so it is
# checked rather than reported.  A phase that shrank the source while leaving
# the surface where it was would have cut in the wrong place, which is exactly
# the mistake this one exists to avoid.
tools/phasecheck.sh "$work" "$f" .cache/symbols/before
if [ "$(cat .cache/symbols/last/after)" -ge "$(cat .cache/symbols/last/before)" ]; then
    echo "  symbols      this phase must lower the count"
    exit 1
fi

make -C "$work" clean >/dev/null 2>&1 || true
if make -C "$work" >/dev/null 2>&1; then
    echo "  build        ok, $before_lines -> $(grep -c '' "$f") lines, $(stat -c%s "$work/pure-vim") bytes"
else
    echo "  build        FAILED -- rerun by hand: make -C $work"
    exit 1
fi

# --- the delta, cumulative --------------------------------------------------
tools/puredelta.sh "$work/pure-vim" "$f" --cases filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd recover '!' 
