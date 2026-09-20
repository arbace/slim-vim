#!/bin/sh
# Whim phase 67 -- no mouse, no spell plumbing, no write-only flags.
# See WHIM-GOAL.md.
#
# Usage: pipes/whim67-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Three cuts, none of which changes what the editor can do, because none of it
# could happen in the first place.
#
#   THE MOUSE, WHICH CANNOT ARRIVE.  There is no 'mouse' option row, and
#       setmouse(), mch_setmouse(), mouse_has() and p_mouse are all gone, so
#       nothing ever asks a terminal to report mouse events.  What served them
#       goes: is_mouse_key() and the term in the input loop that called it,
#       reset_dragwin()/reset_held_button() with dragwin and held_button,
#       mouse_row/mouse_col and old_mouse_row/old_mouse_col -- a save-and-restore
#       pair that nothing else reads -- the 13 mouse rows of key_names_table, the
#       [MOUSE] entry of the terminal string table, and check_termcode()'s mouse
#       matching.  The 26 nv_cmds rows STAY at nv_error: that table's index is a
#       permutation of its rows, so a removed row renumbers the keys after it.
#
#       ONE REAL CHANGE OF BEHAVIOUR IS BURIED HERE, and it is why the pty check
#       below matters.  `looks_like_mouse_start` is not mouse-specific despite
#       its name: it is set for ANY two-byte `ESC [` termcode whose third byte is
#       not a digit, and it defers the match so that a longer code -- a mouse one
#       -- can win instead.  With no mouse code able to arrive, deferring can only
#       lose, so the fold makes such a code match at once.
#
#   THE SPELL PLUMBING.  spellvars_T is one field, win_line()'s spv parameter is
#       already __attribute__((unused)), and win_update() declares one on the
#       stack only to pass its address twice.
#
#   FOURTEEN WRITE-ONLY STATICS.  gcc never warns about these -- a static that is
#       assigned counts as used -- which is the blind spot that hid can_cindent
#       until phase 64 and struct fields until deadfields.py.  Two of them are a
#       whole function body each, so state_no_longer_safe() and its two calls go
#       with was_safe.
#
#   vim_ignored IS NOT ONE OF THEM, though it looks identical to the detector.
#       Its five sites are `vim_ignored = ftruncate(...)`, `= dup(2)` and
#       `= write(1, ...)`: it exists to swallow warn_unused_result, and removing
#       it ADDS warnings.  A (void) cast does not silence that attribute in gcc.
#
# THE DELTA: none.  No key, command or option changes -- every cut is code that
# nothing could reach.  The probes check the editor still starts, edits and
# writes, and the pty check is what would catch the termcode fold going wrong.
set -eu

work=${1:?usage: whim67-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim67 "$f"

# tools/phaserun.sh sweeps next, then runs pipes/whim67-check.sh.
