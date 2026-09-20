#!/bin/sh
# Whim phase 58 -- no language mappings.  See WHIM-GOAL.md.
#
# Usage: pipes/whim58-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# 'iminsert' and 'imsearch' are 0 from here on, so language mappings are never
# active and nothing can make them so:
#
#   :lmap :lnoremap :lunmap :lmapclear   point at ex_ni, and their completion goes
#   CTRL-^ in Insert and on the command line   still consumed, and does nothing;
#       it toggled MODE_LANGMAP and the two options
#   MODE_LANGMAP   never set, so every test of it folds: in edit(), ex_append(),
#       ins_insert(), normal_cmd_get_more_chars()'s r/f/t lookup, getcmdline_int()
#       for / ? @, handle_mapping(), vgetorpeek(), get_map_mode() and
#       map_mode_to_chars()
#   the status line's <lang>   get_keymap_str() only ever printed it
#
# THE DELTA: :lmap, :lnoremap and :lmapclear, now ex_ni.  :lunmap is ex_ni too, and
# its row does not move: bare, it already failed for want of an argument.  The probes check the options
# are unknown, :lmap is refused, and CTRL-^ in Insert mode inserts nothing.
set -eu

work=${1:?usage: whim58-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh edit whim58 "$f"

tools/st.sh cmdidxs "$f" --check >/dev/null

tools/st.sh dropoptions "$f" --local iminsert imsearch

tools/sweep.sh "$f"
tools/st.sh droplocal "$f" b_p_iminsert b_p_imsearch

# tools/phaserun.sh sweeps next, then runs pipes/whim58-check.sh.
