#!/bin/sh
# Whim phase 35 -- no scripts, no session, no autocommands.  See WHIM-GOAL.md.
#
# Usage: pipes/whim35-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Three things that are one question: can the editor be told to do something
# later, or somewhere else, by a file?  A script is commands read from a file, a
# session is a script the editor wrote about itself, and an autocommand is a
# command registered now to run when an event happens.  None of them has
# anywhere to come from: nothing is installed, no vimrc is searched for, and
# the only file read at startup is the one -u names.
#
#   scripts     :source :scriptencoding :scriptversion :vim9script :legacy
#               :vim9cmd's modifier, and 'loadplugins', for plugins never loaded
#   the session :redir :sleep :smile :sandbox,
#               -S session, -s keystroke file, -w/-W keystroke record,
#               'sessionoptions', 'viewoptions', 'viewdir'
#   autocommands :autocmd :augroup :doautocmd :doautoall :noautocmd :filetype
#               :setfiletype, the engine behind them, and 'eventignore'
#
# `-u file` stays, and so do CTRL-Z, :stop and :suspend -- suspending is job
# control, not a session.  See `nosession` for each cut and why.
#
# THE DELTA: the ten rows that succeeded run bare and are not implemented now --
# :sleep, :smile, :vim9script, :autocmd, :augroup, :doautocmd, :doautoall,
# :noautocmd, :sandbox and :filetype.  :source, :redir, :scriptencoding,
# :scriptversion, :legacy and :setfiletype already failed with no argument.  No
# harness sources, redirects, suspends
# or defines an autocommand, and each passes -s only after -e.
set -eu

work=${1:?usage: whim35-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- the rows, then what a row cannot reach ---------------------------------
tools/st.sh retire "$f" source redir sleep smile \
    scriptencoding scriptversion vim9script legacy \
    autocmd augroup doautocmd doautoall noautocmd sandbox filetype setfiletype
tools/st.sh nosession "$f"
# 'eventignore' and 'eventignorewin' go BEFORE the sweep, and without --strict.
# Their shared callback, did_set_eventignore(), calls check_ei(), which reads
# p_ei -- so while either row stands the reader is live, and the sweep cannot
# take it.  The check is the post-condition below: after the sweep, nothing reads
# p_ei and nothing mentions the window field.  eventignorewin is window-local,
# hence --local; nosession.py took its field.
tools/st.sh dropoptions "$f" eventignore
tools/st.sh dropoptions "$f" --local eventignorewin

# No sweep here.  One stood here, and the lines after it were written for swept text,
# but this phase and every stage it has run in reproduce their boundaries without
# it (WHIM-PLAN.md 2c; pipes/whim.stages) -- the stage's one sweep does its work.
# The other rows go once their readers have: a row is what initialises its
# global.
tools/st.sh dropoptions "$f" --strict sessionoptions viewoptions viewdir loadplugins

# tools/phaserun.sh sweeps next, then runs pipes/whim35-check.sh.
