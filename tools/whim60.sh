#!/bin/sh
# Whim phase 60 -- no suffix, case, delay, verbose-file, debug or filter-program options.  See WHIM-GOAL.md.
#
# Usage: tools/whim60.sh <work-dir>      (run from the repository root)
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

work=${1:?usage: whim60.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 - "$f" <<'PY'
TAG = 'nosixopts'
import re, sys
sys.path.insert(0, 'tools')
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

python3 tools/dropoptions.py "$f" suffixes fileignorecase autocompletedelay verbosefile debug
python3 tools/dropoptions.py "$f" --local formatprg equalprg

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
python3 tools/droplocal.py "$f" b_p_fp b_p_ep
tools/sweep.sh "$f"

for g in p_su match_suffix p_fic p_acl delay_pending acl_elapsed p_vfile verbose_fd verbose_open verbose_stop verbose_enter verbose_leave \
         p_debug p_fp b_p_fp p_ep b_p_ep get_equalprg did_set_verbosefile did_set_debug; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  nosixopts    $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  nosixopts    none of the seven options or their readers is left"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
(cd "$d" && HOME="$d" ./vim -e -s '+set sw=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  nosixopts    the control :set sw=3 failed"; exit 1; }
for o in suffixes fileignorecase autocompletedelay verbosefile debug formatprg equalprg; do
    if (cd "$d" && HOME="$d" ./vim -e -s "+set $o?" '+q!' </dev/null >/dev/null 2>&1); then
        echo "  nosixopts    :set $o? was accepted"; exit 1
    fi
done
printf 'aaa bbb\n' > "$d/g.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+set tw=4' '+1normal! gqq' '+wq' g.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/g.txt")" = 'aaa|bbb|' ] || { echo "  nosixopts    gqq with tw=4 left '$(tr '\n' '|' < "$d/g.txt")'"; exit 1; }
echo "  nosixopts    :set sw works; the seven are unknown; gq still formats internally"

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
    setlocal setglobal \
    lmap lnoremap lmapclear
