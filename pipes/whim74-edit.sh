#!/bin/sh
# Whim phase 74 -- no file marks.  See WHIM-GOAL.md.
#
# Usage: pipes/whim74-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# THIS IS THE PHASE THAT WAS ABANDONED AS 70 AND IS NOW REDONE PROPERLY.  The first
# attempt died three times on patterns transcribed from truncated views -- the
# `|| to < from` tail, clrallmarks' `static int i = -1` guard over 26 + 1, and four
# unenumerated adjust sites -- and, worse, its probes MEASURED NOTHING, because a
# mark name like 'A carries a quote that broke the shell quoting so the key was never
# pressed.  Every site below was read verbatim with cat -A first, and every probe was
# calibrated against q73 before being trusted.
#
# WHAT GOES: namedfm[26 + EXTRA_MARKS], which is BOTH the uppercase A-Z file marks
# and the numbered 0-9 marks -- one array, one set of code paths, so they cannot be
# separated.  With one buffer the numbered marks could never be set anyway: viminfo
# is long gone, so they were a store nothing could write.
#
#   mA .. mZ   'A .. 'Z   `A .. `Z   '0 .. '9
#   the cross-file jump: getmark_buf_fnum's arm was the ONLY caller of
#   buflist_getfile(), and of fname2fnum() -- itself already an empty body from
#   phase 70, folded there precisely because the file marks were a separate cut.
#
# WHAT STAYS: the lowercase marks a-z in buf->b_namedm[], and every special mark --
# ' ` " ^ . [ ] < > -- none of which touch namedfm.  :marks still lists what is left
# and :delmarks still clears it; uppercase and digits become "invalid argument".
# fmark_T STAYS: struct taggy embeds it, so the tag stack depends on it.  Only
# xfmark_T, which exists to bolt a filename onto a mark, goes.
#
# SCOPE EVERY EDIT BY FUNCTION.  do_join() has a PARAMETER named `setmark`, so a
# global rename or an unscoped pattern would corrupt it -- the b_next lesson from
# phase 71 in a new costume.
#
# THE DELTA: none expected.  :marks and :delmarks keep their exit status and write
# nothing to stderr for the arguments exsweep uses, and an exsweep row is
# `exit= left= err=`.  Declared empty and left for whimdelta.sh to correct.
set -eu

work=${1:?usage: whim74-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim74 "$f"

tools/st.sh cmdidxs "$f" --check >/dev/null

# tools/phaserun.sh sweeps next, then runs pipes/whim74-check.sh.
