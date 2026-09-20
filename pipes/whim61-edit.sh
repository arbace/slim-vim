#!/bin/sh
# Whim phase 61 -- no window title.  See WHIM-GOAL.md.
#
# Usage: pipes/whim61-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# 'title', 'titlelen', 'titleold', 'titlestring', 'icon' and 'iconstring' go, and
# with them everything that set or restored the terminal's title: maketitle() and
# its thirteen callers, need_maketitle, resettitle(), mch_settitle(),
# mch_restore_title(), set_title_defaults(), term_settitle(), the X11 title and
# icon probes, and the title-stack push at startup and pop at exit.  The editor
# no longer writes to the terminal's title at all.  The t_ts, t_fs, t_ST and t_RT
# terminal codes stay: the terminal codes were kept as a whole.
#
# THE DELTA: none the harnesses record.  The probes check the six are unknown.
set -eu

work=${1:?usage: whim61-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim61 "$f"

tools/st.sh dropoptions "$f" title titlelen titleold titlestring icon iconstring

# tools/phaserun.sh sweeps next, then runs pipes/whim61-check.sh.
