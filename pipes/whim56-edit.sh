#!/bin/sh
# Whim phase 56 -- no shell, runtime or keyword-program options.  See WHIM-GOAL.md.
#
# Usage: pipes/whim56-edit.sh <work-dir> <state-dir>      (run from the repository root)
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

work=${1:?usage: whim56-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

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

tools/st.sh dropoptions "$f" shell shellquote shellredir runtimepath packpath
tools/st.sh dropoptions "$f" --local keywordprg

# No sweep here.  One stood here, and the lines after it were written for swept text,
# but this phase and every stage it has run in reproduce their boundaries without
# it (WHIM-PLAN.md 2c; pipes/whim.stages) -- the stage's one sweep does its work.
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
tools/st.sh droplocal "$f" b_p_kp

# tools/phaserun.sh sweeps next, then runs pipes/whim56-check.sh.
