#!/bin/sh
# Whim phase 59 -- no command-line completion.  See WHIM-GOAL.md.
#
# Usage: pipes/whim59-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# The command line no longer completes anything.  In getcmdline_int() the
# 'wildchar' and 'wildcharm' keys, S-Tab, CTRL-D (list), CTRL-A (insert all),
# CTRL-L (longest match) and CTRL-N/CTRL-P over matches go; each of those keys is
# now an ordinary character, and CTRL-N/CTRL-P browse history as they did with no
# matches.  CTRL-L still adds a character to an incremental search.
#
# What completion shared with filename expansion stays: expand_filename() ->
# ExpandOne() with EXPAND_FILES, and the argument list through expand_wildcards().  So ExpandFromContext() keeps its file branch and loses the
# rest -- options, mappings, buffers, highlight groups, ++opt, every command's
# argument completion -- and ExpandOne() keeps the one mode its last caller asks
# for.  The sweep takes set_one_cmd_context() and everything under it.
#
# The six wild* options go: 'wildchar', 'wildcharm', 'wildmode', 'wildoptions',
# 'wildignore' and 'wildignorecase'.  The last two were read by globbing too, and
# fold as empty and off.
#
# THE DELTA: none the harnesses record.  The probes check the options are unknown
# and that `:e` still edits a named file.
set -eu

work=${1:?usage: whim59-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim59 "$f"

tools/st.sh dropoptions "$f" wildchar wildcharm wildmode wildoptions wildignore wildignorecase

# tools/phaserun.sh sweeps next, then runs pipes/whim59-check.sh.
