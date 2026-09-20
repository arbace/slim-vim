#!/bin/sh
# Zero phase 11 -- `:q` quits, and `ZZ` is `ZQ`.  See ZERO-GOAL.md.
#
# Usage: pipes/zero11-edit.sh <work-dir> <state-dir>     (run from the repository root)
#
# Phases 6 to 10 took every way to reach a file.  What is left of the filesystem in
# this editor is a REFUSAL: `:q` on a modified buffer answers `E37: No write since
# last change (add ! to override)` and stays.  The protection has no remedy once
# nothing can be written -- there is no `:w` to answer it with and no file the text
# could have come from -- so it is a door that opens onto nothing, and this phase
# takes it.  `:q`, `:q!`, `ZZ` and `ZQ` become one thing.
#
# ONE ANCHOR, AND THE PHASE IS THAT FOLD.  `ex_quit()` is
#
#     if ((check_changed(...)) || (check_changed_any(...))) { not_exiting(...); }
#     else                                                  { getout(0); ... }
#
# and the test is the refusal.  Folding it NEVER keeps the `else` -- "quit" -- and
# is the last reference `check_changed()` has.  FIFTEEN FUNCTIONS THEN GO AND THIS
# FILE NAMES NOT ONE OF THEM (ZERO-GOAL.md rule 1), which is the largest surprise
# the phase has: eleven of the fifteen are not the refusal at all.
# `check_changed_any()`'s tail is "go to the buffer that refused" -- it calls
# `set_curbuf()`, which calls `enter_buffer()` and `win_enter_ext()` -- and after
# whim removed the buffer list and the window commands, THAT TAIL WAS THE LAST
# CALLER OF THE WHOLE SWITCH-BUFFER/SWITCH-WINDOW ISLAND.  THE ISLAND IS A GRAPH AND
# NOT A FAN: only `add_bufnum`, `set_curbuf` and `goto_tabpage_win` are called by
# `check_changed_any` itself and the other eight hang off those, so what the edit
# computes before it folds anything is that every call to any of the eleven is inside
# `check_changed_any` or inside another of the eleven.  After this phase the editor
# has no code for entering a different buffer or a different window at all.
#
# `:q` CAN STILL DECLINE, and that is not this phase's: `text_locked()`,
# `curbuf_locked()` and `before_quit_autocmds()` all return early ABOVE the anchor
# and are untouched.  What goes is the refusal that asked whether the text had been
# saved.
#
# THE BUFFER STILL KNOWS IT IS MODIFIED.  `bufIsChanged` and `curbufIsChanged` keep
# their readers -- CTRL-G still prints `[Modified]`, the status line still draws
# `[+]`, `:set modified?` still answers.  What goes is the refusal, not the state.
#
# THERE ARE NO `'confirm'`-STYLE PROMPTS TO WORRY ABOUT: `grep -cw confirm` on the
# input is 0, whim having removed the dialog layer.  Say it, so that the next reader
# does not go looking for one.
#
# TWO EXTRAS GO WITH THE FOLD, each measured byte-identical in the recording.
#
#   A  TWO STRUCT FIELDS THAT BECOME WRITE-ONLY, WHICH NO TOOL CAN SEE.  This is
#      phase 7's `usefilter` judgement in a smaller shape: tools/deadfields.py
#      removes a field nothing NAMES, and gcc has no warning for a member that is
#      only written.  `win_T.w_topline_was_set`'s only reader was in
#      `enter_buffer()` and `wininfo_S.wi_changelistidx`'s only reader was in
#      `get_winopts()`, and the sweep takes both functions.  THE TEXT THIS LEAVES
#      DOES NOT COMPILE -- two mentions survive inside functions the sweep is about
#      to take -- exactly as pipes/zero7-edit.sh says of its own, and that is stated
#      here rather than discovered by whoever runs the edit alone.
#   B  THE TAIL THAT CANNOT RUN.  After the fold `ex_quit()` ends `int save_exiting
#      = exiting; exiting = TRUE; getout(0); not_exiting(save_exiting);`.
#      `getout()` sets `exiting = TRUE` ITSELF and ends in `mch_exit()`, which never
#      returns, so the first, second and fourth statements are dead and gcc cannot
#      prove it.  Replacing the four with `getout(0);` orphans `not_exiting()`, and
#      `not_exiting()` IS the refusal machinery -- `exiting = save_exiting;
#      settmode(TMODE_RAW);`, the "we changed our mind, put the terminal back" -- so
#      it is this phase's and not tidy.  Check `getout()` before folding this on any
#      other tree: the fold is right only because it sets `exiting` for itself.
#
# `ZZ` IS ALREADY `ZQ` AND STAYS SO.  `nv_Zet` runs `do_cmdline_cmd("q!")` for
# `case 'Z'` AND for `case 'Q'`, identical since phase 6.  After this phase `:q` and
# `:q!` are also identical, so all four spellings are one thing.  THE STRINGS ARE
# NOT REWRITTEN TO `"q"`: it would move `zz_key` and `zq_key` for no gain, and
# `case:zz_key` is phase 6's declaration and must not be re-declared here.
#
# WHAT LEAVES FOR A LATER PHASE TO NOTICE.  `SHM_FILEINFO` is the `'shortmess'` `F`
# letter and its only reader was inside `enter_buffer()`; the sweep takes it, and
# the letter is inert afterwards.  That is the options phase's and the flag strings
# are not touched here.
#
# THE INPUT BINARY IS BUILT HERE, before the edit, from the boundary's own makefile
# flags, as every zero edit since phase 2 does, and the source goes with it as
# $state/old.c.  The check needs both: the exit status of a session that quits with
# unsaved changes is what moves, and no recording can see it.
set -eu

work=${1:?usage: zero11-edit.sh <work-dir> <state-dir>}
state=${2:?usage: zero11-edit.sh <work-dir> <state-dir>}
f="$work/zero-vim.c"

# The flags are read out of the boundary's makefile rather than written here a
# second time: zero's compile line is the boundary's (ZERO-GOAL.md rule 8).
cflags=$(sed -n 's/^CFLAGS  *= *//p' "$work/Makefile")
ldflags=$(sed -n 's/^LDFLAGS  *= *//p' "$work/Makefile")
cp "$f" "$state/old.c"
# shellcheck disable=SC2086
( cd "$state" && gcc $cflags $ldflags -o old old.c ) &
pid_old=$!

tools/st.sh edit zero11 "$f"

# An edit that starts a background job waits for it before it exits (tools/phaserun.sh).
wait $pid_old || { echo "  noquit       the input binary did not build with '$cflags' '$ldflags'"; exit 1; }
echo "  noquit       the input is $state/old, $(stat -c%s "$state/old") bytes, beside the source it was built from: a session that types text and then quits with nothing after it exits 1 on that binary and 0 here, and no recording can see it"

# tools/phaserun.sh sweeps next, then runs pipes/zero11-check.sh.
