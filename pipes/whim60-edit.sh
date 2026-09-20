#!/bin/sh
# Whim phase 60 -- no suffix, case, delay, verbose-file, debug or filter-program options.  See WHIM-GOAL.md.
#
# Usage: pipes/whim60-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# Seven options whose default is the only value anything could still act on:
#
#   'suffixes'           ordered wildcard matches, and wildcards have not expanded
#                        since Phase 7 removed globbing; match_suffix() goes
#   'fileignorecase'     off: its five tests fold as false
#   'autocompletedelay'  0: inchar_loop()'s delay is never pending
#   'verbosefile'        empty: the file is never opened, so redir_write(),
#                        redirecting() and the verbose_enter/leave family fold
#   'debug'              empty: emsg_not_now(), emsg_core() and vim_beep() fold
#   'formatprg'          gq through an external program: it only built a
#   'equalprg'           :{range}!prg line, and :! has been ex_ni since Phase 44.
#                        gq and = always take the internal path now.
#
# THE DELTA: none the harnesses record.  The probes check the seven are unknown
# and that gq still formats.
set -eu

work=${1:?usage: whim60-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 - "$f" <<'PY'
TAG = 'nosixopts'
import re, sys
sys.path.insert(0, 'tools')
# tools/cutil.py -- named as a PATH so tools/implhash.sh hashes it into this
# phase's key.  implhash greps for paths and an `import` names a module, so
# without this line an edit to it changes what this phase produces and moves
# no key at all.  See CLAUDE.md on cutil.py and macros.py.  Do not delete it.
import cutil
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()

def die(msg):
    sys.exit('  %-12s %s' % (TAG, msg))

def say(what):
    print('  %-12s %s' % (TAG, what))

def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        die('%s is not defined' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]

def count(s, pattern, n, what):
    k = len(re.findall(pattern, s, re.M))
    if k != n:
        die('%s -- matched %d times, expected %d' % (what, k, n))

def fold_never(s, pattern, what, n=1):
    count(s, pattern, n, what)
    for _ in range(n):
        try:
            s = cutil.fold_never(s, pattern, 1, re.M) if len(re.findall(pattern, s, re.M)) == 1 else _last(s, pattern, cutil.fold_never)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    say(what)
    return s

def _last(s, pattern, f):
    m = list(re.finditer(pattern, s, re.M))[-1]
    start = s.rfind('\n', 0, m.start()) + 1
    return s[:start] + f(s[start:], pattern, 1, re.M)

def drop_if(s, pattern, what):
    count(s, pattern, 1, what)
    try:
        s = cutil.drop_if(s, pattern, flags=re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e))
    say(what)
    return s

def sub(s, pattern, new, what, n=1):
    s, k = re.subn(pattern, new, s, flags=re.M)
    if k != n:
        die('%s -- matched %d times, expected %d' % (what, k, n))
    say(what)
    return s

def literal(s, old, new, what, n=1):
    k = s.count(old)
    if k != n:
        die('%s -- occurs %d times, expected %d' % (what, k, n))
    say(what)
    return s.replace(old, new)

# 'suffixes'
t = in_function(t, 'ExpandOne_start', lambda s: sub(
    s, r'^[ \t]*for \(i = 0; i < 2; \+\+i\)\n[ \t]*\{\n[ \t]*if \(match_suffix\(xp->xp_files\[i\]\)\)\n[ \t]*\{\n[ \t]*\+\+non_suf_match;\n[ \t]*\}\n[ \t]*\}\n', '',
    "a single match chosen by 'suffixes'"))
t = in_function(t, 'expand_wildcards', lambda s: drop_if(s, r'^[ \t]*if \(\*num_files > 1 && !got_int\)$', "matches reordered by 'suffixes'"))

# 'fileignorecase'
t = literal(t, 'regmatch.rm_ic = p_fic;', 'regmatch.rm_ic = FALSE;', "file patterns ignoring case by 'fileignorecase'", 2)
t = in_function(t, 'fname_match', lambda s: literal(s, 'rmp->rm_ic = p_fic || ignore_case;', 'rmp->rm_ic = ignore_case;', "buffer names ignoring case by 'fileignorecase'"))
t = in_function(t, 'vim_fnamecmp', lambda s: drop_if(s, r'^[ \t]*if \(p_fic\)$', 'vim_fnamecmp ignoring case'))
t = in_function(t, 'vim_fnamencmp', lambda s: drop_if(s, r'^[ \t]*if \(p_fic\)$', 'vim_fnamencmp ignoring case'))

# 'autocompletedelay'
def inchar(s):
    s = sub(s, r'^[ \t]*bool delay_pending = [^;]*;\n[ \t]*long acl_elapsed = [^\n]*;\n\n?', '', 'an autocomplete delay that is never pending')
    s = literal(s, ' && !delay_pending', '', 'blocking without waiting on the delay')
    s = fold_never(s, r'^[ \t]*else if \(delay_pending\)$', 'waiting out the autocomplete delay')
    s = drop_if(s, r'^[ \t]*if \(delay_pending && acl_elapsed >= p_acl && maxlen >= 3 && !typebuf_changed\(tb_change_cnt\)\)$', 'the autocomplete delay expiring')
    return s
t = in_function(t, 'inchar_loop', inchar)

# 'verbosefile'
def redirw(s):
    s = drop_if(s, r'^[ \t]*if \(\*p_vfile != NUL && verbose_fd == NULL\)$', "opening 'verbosefile' on first write")
    s = fold_never(s, r'^[ \t]*if \(verbose_fd != NULL\)$', "writing to 'verbosefile'", 2)
    return s
t = in_function(t, 'redir_write', redirw)
t = in_function(t, 'redirecting', lambda s: sub(s, r'return redir_fd != NULL \|\| \*p_vfile != NUL\s*;', 'return redir_fd != NULL;', "redirecting to 'verbosefile'"))
t = in_function(t, 'verbose_enter', lambda s: drop_if(s, r'^[ \t]*if \(\*p_vfile != NUL\)$', "verbose_enter silencing for 'verbosefile'"))
t = in_function(t, 'verbose_leave', lambda s: drop_if(s, r'^[ \t]*if \(\*p_vfile != NUL\)$', "verbose_leave silencing for 'verbosefile'"))
t = sub(t, r'^[ \t]*verbose_(?:enter|leave)\(\);\n', '', 'calls to the emptied verbose_enter and verbose_leave', 4)
t = in_function(t, 'verbose_enter_scroll', lambda s: fold_never(s, r'^[ \t]*if \(\*p_vfile != NUL\)$', "verbose_enter_scroll silencing for 'verbosefile'"))
t = in_function(t, 'verbose_leave_scroll', lambda s: fold_never(s, r'^[ \t]*if \(\*p_vfile != NUL\)$', "verbose_leave_scroll silencing for 'verbosefile'"))

# 'debug'
t = in_function(t, 'emsg_not_now', lambda s: literal(s, "(emsg_off > 0 && vim_strchr(p_debug, 'm') == NULL && vim_strchr(p_debug, 't') == NULL)", '(emsg_off > 0)', "'debug' m and t showing suppressed errors"))
t = in_function(t, 'emsg_core', lambda s: literal(s, "if (!emsg_off || vim_strchr(p_debug, 't') != NULL)", 'if (!emsg_off)', "'debug' t handling errors under emsg_off"))
t = in_function(t, 'vim_beep', lambda s: drop_if(s, r"^[ \t]*if \(vim_strchr\(p_debug, 'e'\) != NULL\)$", "'debug' e showing Beep!"))

# 'formatprg' and 'equalprg'
def pending(s):
    s = literal(s, 'if (oap->op_type == OP_INDENT && *get_equalprg() == NUL)', 'if (oap->op_type == OP_INDENT)', "= through 'equalprg'")
    s = fold_never(s, r'^[ \t]*if \(\*p_fp != NUL \|\| \*curbuf->b_p_fp != NUL\)$', "gq through 'formatprg'")
    return s
t = in_function(t, 'do_pending_operator', pending)
def colon(s):
    s = fold_never(s, r'^[ \t]*if \(oap->op_type == OP_INDENT\)$', "op_colon building an 'equalprg' filter")
    s = fold_never(s, r'^[ \t]*if \(oap->op_type == OP_FORMAT\)$', "op_colon building a 'formatprg' filter")
    return s
t = in_function(t, 'op_colon', colon)

open(path, 'w', errors='surrogateescape').write(t)
PY

tools/st.sh dropoptions "$f" suffixes fileignorecase autocompletedelay verbosefile debug
tools/st.sh dropoptions "$f" --local formatprg equalprg

tools/sweep.sh "$f"
# get_varp()'s "local if set" case for 'equalprg' is written &curbuf->b_p_ep, without
# the parentheses droplocal.py matches -- the same gap as 'keywordprg' in Phase 56.
python3 - "$f" <<'PY'
import re, sys
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()
pat = (r'^[ \t]*case[^\n]*\bBV_EP\b[^\n]*\n[ \t]*return \*curbuf->b_p_ep != NUL\n'
       r'[ \t]*\? \(char_u \*\)&curbuf->b_p_ep : p->var;\n')
t, n = re.subn(pat, '', t, flags=re.M)
if n != 1:
    sys.exit("  nosixopts    get_varp's 'equalprg' case matched %d times, expected 1" % n)
open(path, 'w', errors='surrogateescape').write(t)
print("  nosixopts    get_varp no longer resolves 'equalprg' per buffer")
PY
tools/st.sh droplocal "$f" b_p_fp b_p_ep

# tools/phaserun.sh sweeps next, then runs pipes/whim60-check.sh.
