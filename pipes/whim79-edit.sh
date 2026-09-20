#!/bin/sh
# Whim phase 79 -- the constant-return predicates.  See WHIM-GOAL.md.
#
# Usage: pipes/whim79-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Twenty-eight functions whose whole body is `return <constant>;`.  Each was emptied
# by an earlier phase and left with its callers in place, so the editor still asks
# "is the popup menu visible", "are we in a Vim9 script", "is there more than one
# window" -- and still branches on an answer that cannot change.  The compiler cannot
# help: at -O0 each is a real call and a real branch, and every sweep this pipeline
# runs reports the code as live because it is reachable.  Unuseful, not unused.
#
# THE INVARIANT, AND IT IS ASSERTED RATHER THAN TRUSTED.  Step 1 reads every one of
# the 28 definitions and requires the body to be exactly `return <expected>;`, with
# the expected token written out here.  If an upstream ever gives one a real body,
# the phase fails instead of folding a live predicate.  That is the phase 77 pattern
# ("all EX_BUFNAME commands are ex_ni") and it is the only thing standing between a
# fold and a wrong answer.
#
# FOUR SIMILAR-LOOKING FUNCTIONS ARE NOT TOUCHED, and the distinction is the whole
# reason this phase was surveyed twice.  A scan for `return <single token>;` reports
# 32, but four of those tokens are VARIABLES, not constants:
#
#     get_hislen           -> hislen
#     is_maphash_valid     -> maphash_valid
#     get_search_pat       -> mr_pattern
#     get_text_locked_msg  -> e_not_allowed_to_change_text_or_change_window
#
# My first classifier said thirteen of the 32 returned a variable; it had matched the
# bare tokens 0, 1 and NULL against unrelated declarations elsewhere in the file.
# Reading the DEFINITIONS gives four.  Supplying the expected constant per name, as
# step 1 does, is what makes that mistake impossible to repeat silently.
#
# did_set_number_relativenumber IS A CONSTANT AND IS STILL NOT TOUCHED.  Its only two
# mentions are option-table rows, where it appears as a FUNCTION POINTER with no call
# parentheses.  Folding is meaningless and deleting it would leave two rows pointing
# at nothing.  It stays, and an assertion at the end requires both rows intact.
#
# `binds_out` IS A VETO FOR fold_always, NOT FOR fold_never.  The block at
# parse_command_modifiers' `if (vim9script)` contains a `break` that binds to the
# enclosing `for (;;)`, which is exactly the shape that made buflist_findpat change
# behaviour silently in phase 71 -- but that phase FOLDED A WALK, keeping the body
# while removing the loop around it, so the break rebound.  fold_never DELETES the
# body, break and all, and the condition was false, so the break never fired.  Every
# fold_always site in this phase was audited and none contains an escaping break.
#
# THE SECOND-ORDER CUTS, both proved in the phase rather than assumed:
#
#   skip_for_popup  is not a constant stub on entry -- it has three returns.  Once
#       pum_under_menu and pum_visible fold, both of its guards go and it becomes
#       `return FALSE;`.  Step 5 asserts that with the same const_of() check before
#       step 6 uses it, so the collapse is proved, not hoped for.  Nine more sites.
#
#   may_have_range  is a local of do_one_cmd with two writes.  One is inside the
#       `if (vim9script && ...)` block this phase folds away; the other is that
#       block's else arm, `may_have_range = TRUE;`.  So after the fold it has one
#       write and is constantly true, and its two readers fold too.
#
#   wc  in option_value2string is `long wc = 0;` whose only "write" is `&wc` passed
#       to wc_use_keyname -- which never dereferences wcp.  So BOTH arms of that
#       if/else-if chain are dead, not just the first, and it collapses to the
#       sprintf.  Checked by reading wc_use_keyname's body, not by assuming.
#
#   need_check_timestamps, need_redraw, bom_count  each become write-only once the
#       stub feeding them is gone, so their tests fold and the variables sweep.
#
# ORDERING IS THE MAIN HAZARD AND THE STEPS ARE NUMBERED FOR IT.  Specific literals
# run before blanket regexes, EXCEPT where a blanket edit creates the specific one's
# target.  Three places depend on it: the may_have_range cascade (step 3) only exists
# after step 2a folds the block holding its other write; skip_for_popup's nine sites
# (step 6) only collapse after step 5 empties it; and the two-line ternary at
# do_one_cmd (step 10a) must be replaced BEFORE the blanket current_win_nr pass, or
# that pass eats one of its two halves and leaves a syntax error.  Every anchor in
# this file was counted against the q78 tree before it was written.
#
# NO TERM EDIT ENDS IN WHITESPACE.  `only_one_window() && check_changed_any` becomes
# `check_changed_any` rather than stripping `only_one_window() && `, because a
# literal with a trailing space lost it passing through an editor in phase 71 and the
# match then failed for reasons invisible in the diff.
#
# THE DELTA: none expected.  Every fold removes a branch whose condition cannot hold,
# and every term edit removes a conjunct that is constantly true or a disjunct that
# is constantly false.  The quit path is the one place where getting this wrong is
# silent rather than fatal -- check_more() feeds the four ex_quit/ex_exit conditions
# that decide whether getout(0) runs -- so five quit probes, calibrated on q78, guard
# it directly.  Declared empty, left for whimdelta.sh to correct.
set -eu

work=${1:?usage: whim79-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim79 "$f"

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim79-check.sh.
