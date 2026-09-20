#!/bin/sh
# Whim phase 66 -- no sentences, paragraphs, sections, methods, #if blocks or
# comment blocks.  See WHIM-GOAL.md.
#
# Usage: pipes/whim66-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# One idea, cut at all three places it is reachable from:
#
#   THE MOTIONS  ( and ) by sentence, { and } by paragraph, [[ ]] [] ][ by
#       section, [m ]m [M ]M to a method's braces, [# ]# to the enclosing
#       #if/#endif, and [/ ]/ [* ]* to the enclosing C comment.  The first four
#       rows point at nv_error; the bracket ones go from nv_brackets() and
#       nv_bracket_block().
#   THE TEXT OBJECTS  is, as, ip and ap -- current_sent() and current_par().
#       A sentence you cannot move over is not one you can select either.
#   THE EX ADDRESSES  '{ '} '( ') as line addresses, which get_address() answered
#       with findpar() and findsent().
#
# After which findsent(), findpar() and startPS() have no callers at all, and the
# concept is gone from the editor rather than merely unbound.
#
# WHAT STAYS, and is checked: % and the enclosing-bracket motions [{ ]} [( ]),
# which are findmatchlimit() rather than paragraphs; the ( ) { } [ ] TEXT OBJECTS
# i( a{ i[ and so on, which are current_block(); iw/aw; and the '[ '] '< '> marks,
# which get_address() answers from stored positions.
#
# THE DELTA: none the harnesses record -- no behaviour case moves over a sentence
# or a paragraph, and no Ex command changes.  The probes check each cut key does
# nothing, that [{ and % still move, and that i{ still selects.
set -eu

work=${1:?usage: whim66-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim66 "$f"

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim66-check.sh.
