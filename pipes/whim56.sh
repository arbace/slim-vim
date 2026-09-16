#!/bin/sh
# Whim phase 56 -- no shell, runtime or keyword-program options.  See WHIM-GOAL.md.
#
# Usage: pipes/whim56.sh <work-dir>      (run from the repository root)
#
# Six options whose readers survive only in machinery with nothing to serve:
#
#   'shell', 'shellquote', 'shellredir'  no shell is ever run -- call_shell() and
#       mch_call_shell() went long ago.  'shell' only chose the default of
#       'shellredir' in set_init_3() and whether filename escaping doubled a `!`
#       for csh; 'shellquote' only wrapped do_bang()'s command line.
#   'runtimepath', 'packpath'  there is no runtime to find.  Their readers are the
#       completion of :colorscheme, :compiler, :ownsyntax, :setfiletype, :packadd
#       and :runtime -- every one of them ex_ni -- and of :set ft=, which listed
#       runtime syntax/indent/ftplugin names.
#   'keywordprg'  K is gone; only :set kp= defaulting to :help read it.
#
# THE DELTA: none the harnesses record.  The probes check the six are unknown.
set -eu

work=${1:?usage: whim56.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 - "$f" <<'PY'
import os, re, sys
sys.path.insert(0, 'tools')
import cutil
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()

def die(msg):
    sys.exit('  noshellrtp   ' + msg)

def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        die('%s is not defined' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]

def count_is(s, pattern, n, what):
    k = len(re.findall(pattern, s, re.M))
    if k != n:
        die('%s -- matched %d times, expected %d' % (what, k, n))

def fold_never(s, pattern, what):
    count_is(s, pattern, 1, what)
    try:
        s = cutil.fold_never(s, pattern, 1, re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e))
    print('  noshellrtp   ' + what)
    return s

def drop_if(s, pattern, what):
    count_is(s, pattern, 1, what)
    try:
        s = cutil.drop_if(s, pattern, flags=re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e))
    print('  noshellrtp   ' + what)
    return s

def sub(s, pattern, new, n, what):
    s, k = re.subn(pattern, new, s, flags=re.M)
    if k != n:
        die('%s -- matched %d times, expected %d' % (what, k, n))
    print('  noshellrtp   ' + what)
    return s

# 'shellredir''s default, chosen by the name of 'shell'.
def init3(s):
    s = sub(s, r'^[ \t]*idx_srr = findoption\(\(char_u \*\)"srr"\);\n', '', 1, "set_init_3 looking up 'shellredir'")
    s = fold_never(s, r'^[ \t]*if \(idx_srr < 0\)$', "set_init_3 without a 'shellredir' row")
    s = sub(s, r'^[ \t]*do_srr = !\(options\[idx_srr\]\.flags & P_WAS_SET\);\n', '', 1, "set_init_3 asking whether 'shellredir' was set")
    s = sub(s, r'^[ \t]*p = get_isolated_shell_name\(\);\n', '', 1, "set_init_3 naming the shell")
    s = drop_if(s, r'^[ \t]*if \(p != NULL\)$', "set_init_3 choosing 'shellredir' by shell")
    return s
t = in_function(t, 'set_init_3', init3)
t = in_function(t, 'do_bang', lambda s: drop_if(s, r'^[ \t]*if \(\*p_shq != NUL\)$', "do_bang wrapping the command in 'shellquote'"))
t = in_function(t, 'vim_strsave_fnameescape', lambda s: drop_if(
    s, r'^[ \t]*if \(what == VSE_SHELL && csh_like_shell\(\) && p != NULL\)$', 'filename escaping doubling ! for csh'))

# Completion for commands that are ex_ni, and for :set ft=.
def bycmd(s):
    for c in ('colorscheme', 'compiler', 'ownsyntax', 'setfiletype', 'packadd'):
        s = sub(s, r'^[ \t]*case CMD_%s:\n[ \t]*xp->xp_context = EXPAND_\w+;\n[ \t]*xp->xp_pattern = arg;\n[ \t]*break;\n\n?' % c, '', 1,
                'completing :%s, which is ex_ni' % c)
    s = sub(s, r'^[ \t]*case CMD_runtime:\n[ \t]*set_context_in_runtime_cmd\(xp, arg\);\n[ \t]*break;\n\n?', '', 1,
            'completing :runtime, which is ex_ni')
    return s
t = in_function(t, 'set_context_by_cmdname', bycmd)
def fromctx(s):
    for c in ('COLORS', 'COMPILER', 'OWNSYNTAX', 'FILETYPE', 'PACKADD', 'RUNTIME'):
        s = fold_never(s, r'^[ \t]*if \(xp->xp_context == EXPAND_%s\)$' % c, 'expanding runtime names for EXPAND_%s' % c)
    return s
t = in_function(t, 'ExpandFromContext', fromctx)
def setcmd(s):
    s = drop_if(s, r'^[ \t]*if \(options\[opt_idx\]\.var == \(char_u \*\)&p_ft\)$', ':set ft= completing runtime file types')
    s = fold_never(s, r'^[ \t]*if \(p == \(char_u \*\)&p_pp \|\| p == \(char_u \*\)&p_rtp\)$', "'packpath' and 'runtimepath' completing as directories")
    return s
t = in_function(t, 'set_context_in_set_cmd', setcmd)
t = in_function(t, 'stropt_get_newval', lambda s: fold_never(
    s, r'^[ \t]*if \(varp == \(char_u \*\)&p_kp && \(\*arg == NUL \|\| \*arg == \' \'\)\)$', ":set kp= defaulting to :help"))

open(path, 'w', errors='surrogateescape').write(t)
PY

python3 tools/dropoptions.py "$f" shell shellquote shellredir runtimepath packpath
python3 tools/dropoptions.py "$f" --local keywordprg

tools/sweep.sh "$f"
# get_varp()'s "local if set" case for 'keywordprg' is written &curbuf->b_p_kp,
# without the parentheses droplocal.py's pattern expects, so its two mentions
# would read as readers.  It is plumbing, and goes by hand first.
python3 - "$f" <<'PY'
import re, sys
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()
pat = (r'^[ \t]*case[^\n]*\bBV_KP\b[^\n]*\n[ \t]*return \*curbuf->b_p_kp != NUL\n'
       r'[ \t]*\? \(char_u \*\)&curbuf->b_p_kp : p->var;\n')
t, n = re.subn(pat, '', t, flags=re.M)
if n != 1:
    sys.exit("  noshellrtp   get_varp's 'keywordprg' case matched %d times, expected 1" % n)
open(path, 'w', errors='surrogateescape').write(t)
print("  noshellrtp   get_varp no longer resolves 'keywordprg' per buffer")
PY
python3 tools/droplocal.py "$f" b_p_kp
tools/sweep.sh "$f"

for g in p_kp b_p_kp p_sh p_shq p_srr p_rtp p_pp get_isolated_shell_name csh_like_shell ExpandRTDir \
         ExpandPackAddDir expand_runtime_cmd set_context_in_runtime_cmd did_set_shellpipe_redir; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  noshellrtp   $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  noshellrtp   no shell, runtime-path or keyword-program option or reader is left"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
(cd "$d" && HOME="$d" ./vim -e -s '+set sw=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  noshellrtp   the control :set sw=3 failed"; exit 1; }
for o in shell shellquote shellredir runtimepath packpath keywordprg; do
    if (cd "$d" && HOME="$d" ./vim -e -s "+set $o?" '+q!' </dev/null >/dev/null 2>&1); then
        echo "  noshellrtp   :set $o? was accepted"; exit 1
    fi
done
echo "  noshellrtp   :set sw works; the six are unknown"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd,retab,sort_u,sort_n,ff_dos,binary_mode \
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
    noswapfile \
    setlocal setglobal
