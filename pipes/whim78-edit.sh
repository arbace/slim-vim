#!/bin/sh
# Whim phase 78 -- empty functions, write-only counters, and the window id.
# See WHIM-GOAL.md.
#
# Usage: pipes/whim78-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Three unrelated kinds of leftover, all of them invisible to the compiler and so to
# every sweep this pipeline runs.  A fourth kind -- the constant-return predicates --
# was split out into its own phase after the survey showed it is not one shape but
# several: only about twenty of the twenty-nine sit in a foldable `if`, the rest
# needing term-level or expression edits, and one of them is a function pointer in an
# option table row that must not be touched at all.  Bundling them here would have
# repeated the shape that cost phase 75 eight iterations.
#
# (1) FIFTEEN FUNCTIONS WITH EMPTY BODIES, 49 call sites.  Each was emptied by an
#     earlier phase and left with its callers in place; the call is a no-op that the
#     compiler still emits.  EVERY ONE OF THE 49 IS A BARE STATEMENT -- checked, not
#     assumed: none appears in an if, an assignment or any larger expression, so a
#     line removal cannot corrupt a condition.  That was the trap in phase 75, where
#     ins_apply_autocmds calls were invisible to a regex anchored on `apply_autocmds`.
#
#     nv_nop IS NOT AMONG THEM.  It is empty by design -- the nv_cmds row for KE_NOP
#     -- and nvidxcheck.py requires nv_cmd_idx[] to stay a permutation of the rows.
#
# (2) SIX WRITE-ONLY STATICS.  gcc never warns: assigning to a static counts as using
#     it, which is the can_cindent shape.  Each is incremented and decremented and
#     never read:
#
#       autocmd_blocked         its reader is_autocmd_blocked went in phase 75
#       autocmd_no_enter        ++/-- in create_windows
#       autocmd_no_leave        ++/-- in create_windows
#       redrawing_for_callback  ++/-- in redraw_after_callback
#       prevwin                 written once in win_enter_ext, read nowhere since 75
#       last_win_id             only `w_id = ++last_win_id`, and w_id goes below
#
#     TWO OTHERS ARE FLAGGED BY THE SAME SCAN AND MUST NOT BE TOUCHED.
#     breakcheck_count is READ by `if (++breakcheck_count >= BREAKCHECK_SKIP)`, and
#     vim_ignored is the deliberate sink for discarded return values, kept on purpose
#     in phase 67.  A scanner that counts `++x` as a write and cannot see the read in
#     `x = call()` reports both as write-only.  They are not.
#
#     block_autocmds() and unblock_autocmds() become EMPTY once the counter goes, and
#     they stay that way: they have eight live call sites, one of them deliberately
#     unpaired in deathtrap() -- the process is dying and never unblocks -- so
#     removing calls would touch a signal handler for no gain.
#
# (3) THE WINDOW ID.  With one window, curwin->w_id is a constant, so both
#     `if (is_state.winid != curwin->w_id)` guards in getcmdline_int can never fire.
#     Folding them makes incsearch_state_T.winid write-only, which makes w_id
#     write-only, which makes last_win_id and LOWEST_WIN_ID unread.  One chain.
#     init_incsearch_state keeps a live caller at the top of getcmdline_int, so the
#     function stays; only the two re-initialising guards go.
#
#     The two guards are spelled at DIFFERENT INDENTS -- one at eight spaces, one at
#     twelve -- so they are matched by a regex, not by a literal with a count of two.
#
# (4) ONE DEAD FIELD the field sweep cannot see: cmdarg_T.prechar.  deadfields.py
#     exempts every field of a type that has a positional initialiser anywhere, and
#     cmdarg_T has `cmdarg_T ca = { 0 };` -- which supplies one value and zero-fills
#     the rest, so removing prechar cannot overflow it.
#
#     termrequest_T.tr_start WAS on this list and is NOT removed.  It has a single
#     identifier mention, its declaration, which is what made an audit call it dead --
#     but termrequest_T is positionally initialised three times as {STATUS_GET, -1},
#     and that -1 IS tr_start.  A positional initialiser names nothing, so counting
#     identifiers cannot see the use.  That is the very reason deadfields exempts such
#     types, and the exemption was recorded during the audit and then ignored.
#
# THE DELTA: none expected.  An empty function called or not called does the same
# nothing; a counter nobody reads has no effect; and the two winid guards can never
# fire.  Declared empty, left for whimdelta.sh to correct.
set -eu

work=${1:?usage: whim78-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim78 "$f"

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim78-check.sh.
