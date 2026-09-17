#!/bin/sh
# Whim phase 44 -- no filters, sorting or alignment.  See WHIM-GOAL.md.
#
# Usage: pipes/whim44-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Seven rows go to ex_ni: :! (and :{range}!), :sort, :uniq, :retab, :left,
# :center and :right.  :! was kept in Phase 8 on purpose, as the sentence it
# printed; it is dropped here on request.  The `!` operator key built nothing but
# a :{range}! command line, so its row points at nv_error.  :r !cmd and :w !cmd
# reach do_bang() through :read and :write, not through the :! row, and keep
# Phase 8's refusal: with their ! not special, :w !cmd would write a file of
# that name.
#
# THE DELTA: the six rows that succeeded run bare -- :sort, :uniq, :retab, :left,
# :center, :right -- and the behaviour cases that used them: retab, sort_u and
# sort_n.  :! already differed from Phase 8.
set -eu

work=${1:?usage: whim44-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 tools/retire.py "$f" '!' sort uniq retab left center right
python3 - "$f" <<'EOF'
import re
import sys
sys.path.insert(0, 'tools')
import cutil
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()
t, n = re.subn(r"^([ \t]*\{'!', )nv_operator(, 0, 0\} ,)$", r"\1nv_error\2", t, flags=re.M)
if n != 1:
    sys.exit('whim44: the ! operator row -- matched %d times' % n)
print("  filters      the ! operator's row points at nv_error")
a, z = cutil.find_definition(t, 'set_context_by_cmdname')
s, n = re.subn(r'^[ \t]*case CMD_retab:\n[ \t]*xp->xp_context = EXPAND_RETAB;\n[ \t]*xp->xp_pattern = arg;\n[ \t]*break;\n\n',
               '', t[a:z], flags=re.M)
if n != 1:
    sys.exit('whim44: completion for :retab -- matched %d times' % n)
t = t[:a] + s + t[z:]
print('  filters      completion for :retab')
open(path, 'w', errors='surrogateescape').write(t)
EOF

# tools/phaserun.sh sweeps next, then runs pipes/whim44-check.sh.
