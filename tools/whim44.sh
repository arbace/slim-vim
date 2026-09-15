#!/bin/sh
# Whim phase 44 -- no filters, sorting or alignment.  See WHIM-GOAL.md.
#
# Usage: tools/whim44.sh <work-dir>      (run from the repository root)
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

work=${1:?usage: whim44.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

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

tools/sweep.sh "$f"

for g in ex_bang ex_sort ex_uniq ex_retab ex_align; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  filters      $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  filters      no :!, no sorting, no retab, no alignment; the ! key beeps"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"
python3 tools/arrowcheck.py "$work/whim-vim"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd,retab,sort_u,sort_n \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear colorscheme \
    abbreviate noreabbrev abclear iabbrev inoreabbrev iabclear cabbrev cnoreabbrev cabclear \
    sleep smile vim9script autocmd augroup doautocmd doautoall noautocmd sandbox filetype \
    tab tabedit tabfirst tabmove tablast tabnext tabnew tabonly tabprevious tabNext tabrewind tabs redrawtabline \
    browse confirm mode open tmap tmapclear tnoremap \
    all args argadd argdelete argdedupe argglobal arglocal argument first last rewind \
    sargument sall sfirst slast srewind \
    aboveleft ball belowright botright horizontal leftabove new only resize rightbelow \
    sbuffer sbNext sball sbfirst sblast sbnext sbprevious sbrewind split sunhide sview \
    syncbind topleft unhide vertical vnew vsplit \
    buffer bNext bdelete bfirst blast brewind buffers bwipeout files ls \
    bnext bprevious keepalt \
    center left retab right sort uniq
