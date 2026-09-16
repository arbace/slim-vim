#!/bin/sh
# Whim phase 48 -- no :noswapfile.  See WHIM-GOAL.md.
#
# Usage: tools/whim48.sh <work-dir>      (run from the repository root)
#
# There has been no swap file since Phase 21: the memfile is memory.  The
# modifier set CMOD_NOSWAPFILE, and its two readers, in ml_open() and
# buf_copy_options(), were already empty blocks.  The modifier is matched by name
# before the table, so its branch goes as well as its row.
#
# THE DELTA: the row, which succeeded run bare.
set -eu

work=${1:?usage: whim48.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 tools/retire.py "$f" noswapfile
python3 - "$f" <<'EOF'
import re
import sys
sys.path.insert(0, 'tools')
import cutil
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()

def in_function(name, edit):
    global t
    a, z = cutil.find_definition(t, name)
    t = t[:a] + edit(t[a:z]) + t[z:]

def subn(s, pattern, what):
    s, n = re.subn(pattern, '', s, flags=re.M)
    if n != 1:
        sys.exit('whim48: %s -- matched %d times' % (what, n))
    print('  noswapfile   %s' % what)
    return s

in_function('parse_command_modifiers', lambda s: subn(
    s, r"^[ \t]*case 'n':\n[ \t]*if \(!checkforcmd_noparen\(&eap->cmd, \"noswapfile\", 3\)\)\n"
       r'[ \t]*\{\n[ \t]*break;\n[ \t]*\}\n[ \t]*cmod->cmod_flags \|= CMOD_NOSWAPFILE;\n[ \t]*continue;\n\n',
    'the :noswapfile modifier'))
in_function('set_context_by_cmdname', lambda s: subn(s, r'^[ \t]*case CMD_noswapfile:\n', 'completion for :noswapfile'))
pat = r'^[ \t]*if \(cmdmod\.cmod_flags & CMOD_NOSWAPFILE\)$'
in_function('ml_open', lambda s: cutil.drop_if(s, pat, flags=re.M))
print('  noswapfile   ml_open asking for it')
in_function('buf_copy_options', lambda s: cutil.fold_never(s, pat, 1, re.M))
print('  noswapfile   buf_copy_options asking for it')
n = len(re.findall(r'\bCMOD_NOSWAPFILE\b', t))
if n != 1:
    sys.exit('whim48: CMOD_NOSWAPFILE outside its enumerator -- %d mentions, expected 1' % n)
open(path, 'w', errors='surrogateescape').write(t)
EOF

tools/sweep.sh "$f"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

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
    center left retab right sort uniq \
    qall quitall wall wqall xall \
    startinsert startreplace startgreplace stopinsert \
    noswapfile
