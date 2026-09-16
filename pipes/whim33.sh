#!/bin/sh
# Whim phase 33 -- commands whose machinery has already gone.  See WHIM-GOAL.md.
#
# Usage: pipes/whim33.sh <work-dir>      (run from the repository root)
#
# Every one of these still had a handler, and every one refused or did nothing
# when run with a sensible argument -- measured one by one, in Ex mode, reading
# the message each left:
#
#   shell                  E319, no processes since phase 8
#   gui gvim               E25, no GUI in this build
#   cdo cfdo ldo lfdo      E319, no quickfix lists
#   vim9cmd                E319, no eval layer
#   endclass endinterface  Vim9 class keywords, invalid without the eval layer
#   endenum public static this
#   digraphs               E196, no digraphs in this build
#   redrawtabpanel         E1547, no tab panel
#   colorscheme            E185, no colour scheme to find: nothing is installed
#
# A command that only says no is a row pointing at a handler that exists to say
# no, so the row goes to ex_ni -- WHIM-GOAL.md rule 3, the table keeps its
# shape -- and the sweep takes the handlers nothing else uses.  `:!` is the one
# refusal kept, on purpose: `:!cmd`, `:r !cmd` and `:w !cmd` are how a user
# reaches for a process, and phase 8's answer to that is the sentence it prints.
#
# ex_listdo also serves :argdo, :bufdo, :windo and :tabdo, so it stays; its two
# tests for the quickfix commands can never be true once those rows point
# elsewhere, and they are folded rather than left asking.
#
# THE DELTA: colorscheme.  Run bare it reported the scheme in slim-vim and
# succeeded; it is not implemented now.  Every other row already failed, or is
# one the sweep skips because it hands over the terminal.
set -eu

work=${1:?usage: whim33.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

# --- the rows ------------------------------------------------------------------
python3 tools/retire.py "$f" shell gui gvim cdo cfdo ldo lfdo vim9cmd \
    endclass endinterface endenum public static this \
    digraphs redrawtabpanel colorscheme

# --- ex_listdo's questions about commands that no longer reach it ---------------
python3 - "$f" <<'EOF'
import re
import sys
sys.path.insert(0, 'tools')
import cutil
path = sys.argv[1]
text = open(path, errors='surrogateescape').read()
a, z = cutil.find_definition(text, 'ex_listdo')
body = text[a:z]
for what, pattern in (
    ('the winfixbuf refusal for :ldo and :lfdo',
     r'^[ \t]*if \(\(eap->cmdidx == CMD_ldo \|\| eap->cmdidx == CMD_lfdo\) && !eap->forceit\)$'),
    ('the quickfix commands answering not implemented',
     r'^[ \t]*if \(eap->cmdidx == CMD_cdo \|\| eap->cmdidx == CMD_ldo \|\| eap->cmdidx == CMD_cfdo \|\| eap->cmdidx == CMD_lfdo\)$'),
):
    try:
        body = cutil.fold_never(body, pattern, 1, re.M)
    except ValueError as e:
        sys.exit('whim33: %s -- %s' % (what, e))
    print('  listdo       %s: gone' % what)
open(path, 'w', errors='surrogateescape').write(text[:a] + body + text[z:])
EOF

tools/sweep.sh "$f"

# The post-condition, asked after the sweep because it is the sweep that takes
# the handlers: nothing that existed only to refuse is left, and ex_listdo no
# longer names a quickfix command.
for g in ex_shell ex_nogui ex_digraphs ex_redrawtabpanel ex_colorscheme load_colors; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  deadcmds     $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
if python3 - "$f" <<'EOF'
import re, sys
sys.path.insert(0, 'tools')
import cutil
text = open(sys.argv[1], errors='surrogateescape').read()
a, z = cutil.find_definition(text, 'ex_listdo')
sys.exit(0 if re.search(r'\bCMD_(cdo|cfdo|ldo|lfdo)\b', text[a:z]) else 1)
EOF
then
    echo "  deadcmds     ex_listdo still tests for a quickfix command"
    exit 1
fi
echo "  deadcmds     no handler that only refused is left, and ex_listdo asks nothing about quickfix"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd \
    helpclose intro version cd chdir lcd lchdir tcd tchdir pwd '!' language \
    tags preserve swapname mkvimrc mkexrc checktime command comclear colorscheme
