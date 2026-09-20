#!/bin/sh
# Whim phase 6 -- the editor stops writing shell scripts, and stops drawing a
# completion menu.  See WHIM-GOAL.md.
#
# Usage: pipes/whim6-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Two cuts, both at the boundary between the editor and everything outside it.
#
# WILDCARDS.  `expand_wildcards()` has two expanders behind it and only one is
# the editor's own.  `gen_expand_wildcards()` walks directories itself and
# handles *, ?, [...], ~ and $VAR without leaving the process; what it cannot do
# it hands to `mch_expand_wildcards()`, which sniffs 'shell' for csh, zsh or
# bash, picks one of five quoting styles, writes a shell function into a
# temporary file, runs it and parses back a NUL-separated list.  That second one
# is the editor doing the shell's job in 250 lines.  Shell-out itself STAYS --
# `:!`, `:%!`, `:r !` are untouched -- but the editor stops generating shell to
# expand a pattern.  What reaches it is now passed through literally.
#
# WILDMENU.  'wildmenu' draws the completion matches in the status line and
# rebinds the arrow keys to walk them; 'wildoptions'=pum draws the same matches
# as a popup.  Both are a display of what Tab completion already computed.
#
# The second cut is the one that needed doing by hand, and the reason is worth
# keeping: p_wmnu is read at thirteen places, and the dead-code sweep counts
# references.  A variable that is never assigned TRUE makes every one of those
# branches unreachable and every one of them is still a reference, so the sweep
# sees a live option.  Folding it to FALSE at the source turns thirteen
# reachability questions into the one question the sweep can answer.
#
# The popup form goes for the mirror image of that reason: with the option gone
# `cmdline_pum_active()` can only answer FALSE while still being CALLED ten
# times, which keeps two hundred lines alive that can no longer run.  The popup
# menu ITSELF stays -- pum_display() has a second caller in insert-mode
# completion -- and only the command line's use of it is cut.
#
# THE DELTA: `:e {a,b}.txt` and backticks in a file argument stop expanding and
# name a file literally; `:e *.c`, `:e ~/x`, `:e $HOME/x` and file-name
# completion are the native path and do not move.  'wildmenu' and the `pum`
# value of 'wildoptions' stop existing; Tab completion behaves as it does with
# `set nowildmenu`, which is what this build now always is.  No Ex command
# changes, and the libc surface does not move at all -- shell-out keeps fork,
# execvp, pipe and waitpid, and opendir/readdir are held by the TEMP DIRECTORY
# (vim_opentempdir, and delete_recursive via readdir_core) as much as by the
# native expander, so cutting the expander would not take them either.  That
# was expected.  This phase buys complexity, not dependencies.
set -eu

work=${1:?usage: whim6-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the two entry points ---------------------------------------------
tools/st.sh nowild "$f"
tools/st.sh nowildmenu "$f"
tools/st.sh dropoptions "$f" wildmenu

# tools/phaserun.sh sweeps next, then runs pipes/whim6-check.sh.
