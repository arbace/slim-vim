#!/bin/sh
# Whim phase 64 -- no formatting, comment or nroff-macro options.  See WHIM-GOAL.md.
#
# Usage: pipes/whim64-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Five options, and the machinery that only they gave a meaning to:
#
#   'comments'       no comment leader is recognised any more.  get_leader_len()
#       and get_last_leader_offset() would return 0 and -1, so everything built
#       on a leader goes: open_line() copying, replacing and aligning one,
#       insertchar() completing a comment's end, J removing leaders, the leader
#       a formatted or wrapped line keeps, same_leader(), skip_comment(), the
#       declaration search skipping comment lines, and % skipping a // comment
#       in a buffer whose 'comments' looked like C.
#   'formatoptions'  fixed at its default, "tcq".  With no leader, 'c' and 'q'
#       have nothing to act on, so what is left is 't': text still wraps at
#       'textwidth' while typing, and gq still formats.  Every other flag was
#       off, so its code goes: 'a' (auto_format(), check_auto_format() and the
#       18 calls), 'w', 'n', '2', 'b', 'l', 'v', 'm', 'M', 'B', '1', 'p', ']',
#       'j', 'r', 'o' and '/'.  'paste' still stops the wrapping, as it did.
#   'formatlistpat'  only 'n' read it, through get_number_indent().
#   'paragraphs', 'sections'  no nroff macro starts a paragraph or section: {, },
#       [[, ]], ( and ) and the ip/ap text objects stop at blank lines, form
#       feeds and braces, and inmacro() goes.
#
# And the two mechanisms that were left reading what those options described:
#
#   THE FORMAT OPERATOR  gq and gw, their doubled gqq/gqgq/gww/gwgw, op_format(),
#       format_lines() and fmt_check_par().  A paragraph is only a paragraph to
#       decide where a format stops, and nothing formats now.  What stays is the
#       wrap while typing: 'textwidth' and 'wrapmargin' still break a line
#       through insertchar() and internal_format(), and 'paste' still stops it.
#       With no gq, INSCHAR_FORMAT is never set and comp_textwidth() loses the
#       flag that chose the screen width for it.
#   GO TO LOCAL DECLARATION  gd and gD, nv_gd() and find_decl(), which searched
#       from the start of the block the cursor was in.  gd was the only caller.
#   THE = OPERATOR  ==, =G and the rest.  op_reindent() re-applied get_indent(),
#       which is the indent the line already has: 'equalprg' went in phase 60 and
#       C-indenting is off, so = could not compute an indent to apply.
#   THE ! OPERATOR  !{motion}, which was ALREADY dead -- its nv_cmds row has been
#       nv_error for phases, and get_op_type() is reached only from nv_operator()
#       -- so OP_FILTER could no longer be set at all.  What goes is the dispatch
#       nothing reached: the OP_FILTER case, the `!` op_colon() typed after a
#       range, and do_bang()'s bangredo block, which only that case set.
#       :w !cmd and :r !cmd still reach do_bang(), and do_filter() still says the
#       command is not available in this version.
#   WHAT C-INDENTING LEFT BEHIND  the engine went phases ago -- no get_c_indent(),
#       no cin_* anything, no 'cindent', 'cinoptions', 'cinkeys', 'cinwords',
#       'indentexpr' or 'indentkeys'.  What stayed was a switch wired to FALSE and
#       its plumbing: cindent_on(), which is `return FALSE`, and can_cindent,
#       WRITTEN IN TEN PLACES AND READ IN NONE -- gcc does not warn, because a
#       static that is assigned counts as used.  set_can_cindent() goes with it.
#       'smartindent' STAYS: may_do_si(), did_si/can_si/can_si_back/no_si and
#       open_line()'s {, }, # and ) rules are a different mechanism, and this
#       build switches it on by default.
#
# THE DELTA: three behaviour cases -- format_gq (gqq now beeps and changes
# nothing) and the two that set the options, format_comment and open_comment.
# The probes check the five options are unknown, that typing still wraps at
# 'textwidth', that gqq and gd do nothing, and that } no longer stops at .PP.
set -eu

work=${1:?usage: whim64-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim64 "$f"

tools/st.sh dropoptions "$f" paragraphs sections
tools/st.sh dropoptions "$f" --local formatoptions formatlistpat comments

tools/sweep.sh "$f"
for v in b_p_fo b_p_flp b_p_com; do
    tools/st.sh droplocal "$f" $v
done

# tools/phaserun.sh sweeps next, then runs pipes/whim64-check.sh.
