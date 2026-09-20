#!/bin/sh
# Whim phase 81 -- one line, one command.  See WHIM-GOAL.md.
#
# Usage: pipes/whim81-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# An Ex line could hold several commands separated by `|`, and end in a `"`
# comment.  Both existed for scripts -- a vimrc, a sourced file, a function body --
# and this editor reads none: every command it runs was typed, came from `+cmd`, or
# came from a mapping's right-hand side.  So a line is one command now, and `|` and
# `"` are ordinary characters in its argument.
#
# THE MACHINERY IS SMALL AND IN ONE PLACE.  separate_nextcmd() split a bar-splitting
# (EX_TRLBAR) command's argument at the first unescaped `|`, `"` or newline;
# check_nextcmd(), find_nextcmd(), ends_excmd() and ends_excmd2() each knew the same
# three characters; and a handful of callers knew them again -- :substitute's tail,
# the trailing-characters check in do_one_cmd, :append's `:a|text`, `:|` printing the
# line, and the whole-line `:" comment`.
#
# A NEWLINE STILL ENDS A COMMAND.  "One line, one command" is exactly that rule, and
# the newline branch of separate_nextcmd is kept as it was, backslash and all.
#
# DECIDED BEFORE THIS WAS WRITTEN, and each is probed below:
#   `a|b`      the bar is argument text.  A command without EX_EXTRA reports E488
#              trailing characters; one with it takes the bar as part of its argument.
#   `a " x`    the quote is argument text too, so a trailing comment is an error or
#              an argument, and `:" x` is E492.
#   `\|`       means nothing special: the backslash stays, so `:map Q A\|b` maps to
#              `A\|b` where it used to map to `A|b`.  `\"` likewise.  CTRL-V handling
#              is unchanged.
#
# KEPT, deliberately: EX_NOTRLCOM.  Its comment meaning is gone, but it still decides
# whether separate_nextcmd strips trailing spaces, and that is what lets a mapping's
# right-hand side end in a space.  Behaviour, not comment syntax, so it stays.
#
# THE DELTA.  No behaviour case, no terminal row and no swept command uses a bar or a
# comment, so the cumulative list is phase 80's unchanged.  What moves is probed
# directly: a corpus of lines through the q80 binary and this one, with the lines
# expected to differ written out, and everything else required identical.
set -eu

work=${1:?usage: whim81-edit.sh <work-dir> <state-dir>}
state=${2:?usage: whim81-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

cp "$f" "$state/old.c"
(cd "$state" && gcc -O0 -static -s -w -o old old.c) &
pid_old=$!

tools/st.sh edit whim81 "$f"

wait $pid_old

# tools/phaserun.sh sweeps next, then runs pipes/whim81-check.sh.
