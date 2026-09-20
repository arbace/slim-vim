#!/bin/sh
# Whim phase 48 -- no :noswapfile.  See WHIM-GOAL.md.
#
# Usage: pipes/whim48-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# There has been no swap file since Phase 21: the memfile is memory.  The
# modifier set CMOD_NOSWAPFILE, and its two readers, in ml_open() and
# buf_copy_options(), were already empty blocks.  The modifier is matched by name
# before the table, so its branch goes as well as its row.
#
# THE DELTA: the row, which succeeded run bare.
set -eu

work=${1:?usage: whim48-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

tools/st.sh retire "$f" noswapfile
python3 - "$f" <<'EOF'
import re
import sys
sys.path.insert(0, 'tools')
# tools/cutil.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
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

# tools/phaserun.sh sweeps next, then runs pipes/whim48-check.sh.
