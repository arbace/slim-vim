#!/bin/sh
# Whim phase 7 -- the editor stops looking for files it was not given.
#
# Usage: pipes/whim7-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Two things go, and they are the same thing seen from two sides: the editor
# asking the filesystem what is around it.
#
# WILDCARDS.  Phase 6 removed the expander that wrote shell scripts; this
# removes the editor's own.  `gen_expand_wildcards()` walked directories with
# opendir and readdir to match *, ?, [...], ~ and $VAR, and now hands every
# pattern back unchanged -- which is the path vim already took for a pattern
# with no wildcard in it.  A shell expands `*.c` before vim ever sees it.
#
# THE CURRENT DIRECTORY.  :cd, :chdir, :lcd, :lchdir, :tcd, :tchdir and :pwd.
# A process with a notion of "where I am" that the user can move is a process
# with a filesystem; an embedded editor handed a buffer has neither.
#
# Two things this does NOT do, both of which look as though it should:
#
#   * opendir/readdir do not go.  They are held by the TEMP DIRECTORY --
#     vim_opentempdir, and delete_recursive via readdir_core -- which exists so
#     :%!sort has somewhere to put a file.  That dies with shell-out in phase
#     12, not with globbing here.  Measured, not assumed.
#   * getcwd does not go either.  It is mch_dirname, and :cd/:pwd are two of
#     its eleven callers; the rest are buf_modname, mch_FullName,
#     shorten_fnames and the file finder, which resolve a path the user named.
#
# THE DELTA: `:e *.c` opens one buffer called `*.c`, and file-name completion
# stops working -- `:e ali<Tab>` gave `alias.c` and now gives `ali\*`.  Seven
# command names report "not implemented" instead of changing or printing the
# working directory.
#
# And one this phase did not predict, which the check caught rather than the
# author: **:recover moves too.**  recover_names() looks for swap files by
# building the patterns "*.sw?", ".*.sw?" and ".sw?" and expanding them, so an
# editor that does not expand patterns cannot find a swap file it was not told
# the name of.  That is a consequence of removing globbing, not a bug in it,
# and it is declared rather than explained away -- which is the difference
# between a delta list and a list widened to fit.
set -eu

work=${1:?usage: whim7-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the two entry points ---------------------------------------------
tools/st.sh noglob "$f"
tools/st.sh retire "$f" cd chdir lcd lchdir tcd tchdir pwd

# tools/phaserun.sh sweeps next, then runs pipes/whim7-check.sh.
