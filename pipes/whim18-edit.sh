#!/bin/sh
# Whim phase 18 -- nothing is read at startup, and nothing on the command line
# decides anything any more.  See WHIM-GOAL.md.
#
# Usage: pipes/whim18-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# TWO CUTS IN ONE PHASE, and they are one question: what may the invocation
# say?
#
# THE FILES.  source_startup_scripts() looked for a vimrc in five places, an
# exrc in the current directory, and a plugin in every directory of
# 'runtimepath'.  It reads nothing at all now -- not even a file named with -u,
# which goes too -- and 'exrc', the option that let a directory carry its own
# configuration, goes with it.
#
# -u GOES HERE, not later, so that no tool depends on it.  -u NONE was how a
# harness kept a vimrc out of a recorded run; once nothing is searched for, it
# is a no-op, and every harness now isolates the editor with an empty $HOME,
# $VIM and $VIMRUNTIME instead, which holds for slim-vim too.
#
# THE FLAGS.  What is left of the command line is what the flags still decide,
# and several of them no longer decide anything: -y and -Z chose modes whose
# machinery has gone, and 'viminfo' and 'viminfofile' name a file nothing reads
# or writes.
#
# THEY ARE ONE PHASE because the second is what the first leaves behind: a flag
# is only pointless once the thing it selected is gone.
#
# THE DELTA: none the harness records.  No harness passes -u.
set -eu

work=${1:?usage: whim18-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the entry points -------------------------------------------------
tools/st.sh nostartup "$f"
tools/st.sh dropoptions "$f" --strict exrc
tools/st.sh dropopts "$f" -y -Z -u
tools/st.sh nocmdopts "$f"
tools/st.sh dropoptions "$f" --strict viminfo viminfofile

# tools/phaserun.sh sweeps next, then runs pipes/whim18-check.sh.
