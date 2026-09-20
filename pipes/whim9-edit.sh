#!/bin/sh
# Whim phase 9 -- the editor stops asking the environment what language it is
# in.  See WHIM-GOAL.md.
#
# Usage: pipes/whim9-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# `setlocale(LC_ALL, "")` reads $LANG, $LC_ALL and $LC_CTYPE at startup and
# changes how this process compares strings, classifies characters and formats
# a time.  :language lets the user change it again.  enc_locale() derives
# 'encoding' from nl_langinfo(CODESET).  All of it is the editor taking
# instruction from the environment it happens to be started in.
#
# ONE EDIT HERE IS NOT A REMOVAL, and the phase is wrong without it.
# 'encoding' compiles in as **latin1**.  It is only ever utf-8 because
# set_init_default_encoding() asks the locale at startup and overwrites the
# default with the answer.  Remove that call alone and this silently becomes a
# latin1 editor -- every multibyte motion, every :s over non-ASCII, every file
# read.  So the default becomes utf-8 in the same edit.
#
# That is not a behaviour change on this target, and it was checked rather than
# assumed: musl answers UTF-8 to nl_langinfo(CODESET) unconditionally, so the
# derived value was already utf-8, with $LANG set and with $LANG unset.  The
# change makes the encoding a property of the build instead of the machine.
#
# The four lang* options go too.  All four are wired to (char_u *)NULL -- they
# accept a value and store it nowhere -- so they are Phase 3's rule arriving
# late rather than a new decision, and no behaviour can change.
#
# THE DELTA: :language reports that it is not available.  Nothing else: the
# process runs in the C locale now, which is what it was already running in for
# every purpose this build has.
set -eu

work=${1:?usage: whim9-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

# --- cut the locale layer -------------------------------------------------
tools/st.sh nolocale "$f"
tools/st.sh retire "$f" language
tools/st.sh dropoptions "$f" langmap langmenu langnoremap langremap

# tools/phaserun.sh sweeps next, then runs pipes/whim9-check.sh.
