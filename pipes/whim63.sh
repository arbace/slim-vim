#!/bin/sh
# Whim phase 63 -- no jump list.  See WHIM-GOAL.md.
#
# Usage: pipes/whim63.sh <work-dir>      (run from the repository root)
#
# The per-window jump list goes: w_jumplist, w_jumplistlen and w_jumplistidx,
# setpcmark() appending to it, CTRL-O and CTRL-I walking it through movemark(),
# :jumps and :clearjumps, cleanup_jumplist(), copying it to a new window and
# freeing it with one, and the loops that kept its marks right when lines moved
# or a file was forgotten.
#
# What stays, because it is not the jump list: the previous-context mark behind
# '' and `` (w_pcmark, still set by setpcmark()), the change list and g; g,
# (nv_pcmark() keeps that half), :keepjumps (it guards the pcmark and the change
# list too), and JUMPLISTSIZE, which sizes the change list.  CTRL-O in Select mode
# still runs one Visual command; anywhere else CTRL-O and CTRL-I beep.
#
# THE DELTA: :jumps and :clearjumps, now ex_ni.  The probes check CTRL-O no longer
# jumps back, '' still does, and :jumps is refused.
set -eu

work=${1:?usage: whim63.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 - "$f" <<'PY'
TAG = 'nojumplist'
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


def repeat(s, pattern, what, n, f):
    count(s, pattern, n, what)
    for _ in range(n):
        try:
            s = _last(s, pattern, f)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    say('%s (%d)' % (what, n))
    return s


for c, h in (('jumps', 'ex_jumps'), ('clearjumps', 'ex_clearjumps')):
    t = sub(t, r'^([ \t]*\[CMD_%s\] = \{\(char_u \*\)"%s", sizeof\("%s"\) - 1, )%s,' % (c, c, c, h), r'\1ex_ni,', ':%s points at ex_ni' % c)
t = sub(t, r'^([ \t]*\{Ctrl_I, )nv_pcmark(, 0, 0\} ,)', r'\1nv_error\2', 'CTRL-I in Normal mode points at nv_error')

def pcmark(s):
    m = re.search(r'^[ \t]*if \(\+\+curwin->w_jumplistlen > JUMPLISTSIZE\)$', s, re.M)
    z = s.find('fm->fname = NULL;\n')
    if not m or z < 0 or s.count('fm->fname = NULL;\n') != 1:
        die('setpcmark -- the jump-list append was not found once')
    say('setpcmark appending to the jump list')
    return s[:m.start()] + s[z + len('fm->fname = NULL;\n'):]
t = in_function(t, 'setpcmark', pcmark)

def ctrlo(s):
    s = sub(s, r'^([ \t]*)cap->count1 = -cap->count1;\n[ \t]*nv_pcmark\(cap\);\n', r'\1clearopbeep(cap->oap);\n', 'CTRL-O walking back through the jump list')
    return s
t = in_function(t, 'nv_ctrlo', ctrlo)

def pc(s):
    s = drop_if(s, r'^[ \t]*if \(cap->cmdchar == TAB && mod_mask == MOD_MASK_CTRL\)$', 'CTRL-Tab refused by the jump-list command')
    s = sub(s, r"^([ \t]*)if \(cap->cmdchar == 'g'\)\n[ \t]*\{\n[ \t]*pos = movechangelist\(\(int\)cap->count1\);\n[ \t]*\}\n[ \t]*else\n[ \t]*\{\n[ \t]*pos = movemark\(\(int\)cap->count1\);\n[ \t]*\}\n",
            r'\1pos = movechangelist((int)cap->count1);\n', 'the jump list as the other half of nv_pcmark')
    s = sub(s, r"^([ \t]*)else if \(cap->cmdchar == 'g'\)$", r'\1else', 'the change-list messages no longer choosing by key')
    s = sub(s, r'^[ \t]*else\n[ \t]*\{\n[ \t]*clearopbeep\(cap->oap\);\n[ \t]*\}\n', '', 'a jump-list miss beeping')
    return s
t = in_function(t, 'nv_pcmark', pc)

def lockmarks(s):
    s = drop_if(s, r'^[ \t]*for \(i = 0; i < win->w_jumplistlen; \+\+i\)$', 'line changes moving jump-list marks')
    s = sub(s, r'^[ \t]*if \(\(cmdmod\.cmod_flags & CMOD_LOCKMARKS\) == 0\)\n[ \t]*\{\n[ \t]*\}\n\n?', '', "the now-empty 'lockmarks' test around them")
    return s
t = in_function(t, 'mark_adjust_internal', lockmarks)
t = in_function(t, 'mark_col_adjust', lambda s: drop_if(s, r'^[ \t]*for \(i = 0; i < win->w_jumplistlen; \+\+i\)$', 'column changes moving jump-list marks'))
t = in_function(t, 'mark_forget_file', lambda s: drop_if(s, r'^[ \t]*for \(i = wp->w_jumplistlen - 1; i >= 0; --i\)$', 'a forgotten file leaving the jump list'))
t = in_function(t, 'fmarks_check_names', lambda s: sub(
    s, r'^[ \t]*for \(\(wp\) = firstwin; \(wp\) != NULL; \(wp\) = \(wp\)->w_next\)\s*\n[ \t]*\{\n[ \t]*for \(i = 0; i < wp->w_jumplistlen; \+\+i\)\n[ \t]*\{\n[ \t]*fmarks_check_one\(&wp->w_jumplist\[i\], name, buf\);\n[ \t]*\}\n[ \t]*\}\n\n?',
    '', 'a named buffer resolving jump-list file names'))
t = in_function(t, 'win_init', lambda s: sub(s, r'^[ \t]*copy_jumplist\(oldp, newp\);\n', '', 'a new window copying the jump list'))
t = in_function(t, 'win_free', lambda s: sub(s, r'^[ \t]*free_jumplist\(wp\);\n\n?', '', 'a closed window freeing the jump list'))

open(path, 'w', errors='surrogateescape').write(t)
PY

python3 tools/create_cmdidxs.py "$f" --check >/dev/null

tools/sweep.sh "$f"

for g in w_jumplist w_jumplistlen w_jumplistidx movemark cleanup_jumplist copy_jumplist free_jumplist ex_jumps ex_clearjumps; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  nojumplist   $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
grep -q 'w_pcmark' "$f" || { echo "  nojumplist   w_pcmark went too -- the '' mark was not the jump list's"; exit 1; }
grep -q 'movechangelist' "$f" || { echo "  nojumplist   movechangelist went too -- g; and g, were not the jump list's"; exit 1; }
echo "  nojumplist   no jump list is left; the '' mark and the change list are"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
if (cd "$d" && HOME="$d" ./vim -e -s '+jumps' '+q!' </dev/null >/dev/null 2>&1); then
    echo "  nojumplist   :jumps was accepted"; exit 1
fi
printf 'a\nb\nc\n' > "$d/j.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' '+normal! 3G' "$(printf '+normal! \017')" '+s/^/X/' '+wq' j.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/j.txt")" = 'a|b|Xc|' ] || { echo "  nojumplist   CTRL-O moved the cursor: '$(tr '\n' '|' < "$d/j.txt")'"; exit 1; }
printf 'a\nb\nc\n' > "$d/k.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+1' "+normal! 3G''" '+s/^/Y/' '+wq' k.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/k.txt")" = 'Ya|b|c|' ] || { echo "  nojumplist   '' did not return to line 1: '$(tr '\n' '|' < "$d/k.txt")'"; exit 1; }
echo "  nojumplist   :jumps is refused; CTRL-O stays put; '' still jumps back"

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
    lmap lnoremap lmapclear \
    jumps clearjumps
