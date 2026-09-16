#!/bin/sh
# Whim phase 58 -- no language mappings.  See WHIM-GOAL.md.
#
# Usage: pipes/whim58.sh <work-dir>      (run from the repository root)
#
# 'iminsert' and 'imsearch' are 0 from here on, so language mappings are never
# active and nothing can make them so:
#
#   :lmap :lnoremap :lunmap :lmapclear   point at ex_ni, and their completion goes
#   CTRL-^ in Insert and on the command line   still consumed, and does nothing;
#       it toggled MODE_LANGMAP and the two options
#   MODE_LANGMAP   never set, so every test of it folds: in edit(), ex_append(),
#       ins_insert(), normal_cmd_get_more_chars()'s r/f/t lookup, getcmdline_int()
#       for / ? @, handle_mapping(), vgetorpeek(), get_map_mode() and
#       map_mode_to_chars()
#   the status line's <lang>   get_keymap_str() only ever printed it
#
# THE DELTA: :lmap, :lnoremap and :lmapclear, now ex_ni.  :lunmap is ex_ni too, and
# its row does not move: bare, it already failed for want of an argument.  The probes check the options
# are unknown, :lmap is refused, and CTRL-^ in Insert mode inserts nothing.
set -eu

work=${1:?usage: whim58.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 - "$f" <<'PY'
import re, sys
sys.path.insert(0, 'tools')
import cutil
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()

def die(msg):
    sys.exit('  nolangmap    ' + msg)

def say(what):
    print('  nolangmap    ' + what)

def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        die('%s is not defined' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]

def once(s, pattern, what):
    k = len(re.findall(pattern, s, re.M))
    if k != 1:
        die('%s -- matched %d times, expected 1' % (what, k))

def fold_never(s, pattern, what):
    once(s, pattern, what)
    try:
        s = cutil.fold_never(s, pattern, 1, re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e))
    say(what)
    return s

def drop_if(s, pattern, what):
    once(s, pattern, what)
    try:
        s = cutil.drop_if(s, pattern, flags=re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e))
    say(what)
    return s

def literal(s, old, new, what, n=1):
    k = s.count(old)
    if k != n:
        die('%s -- occurs %d times, expected %d' % (what, k, n))
    say(what)
    return s.replace(old, new)

def sub(s, pattern, new, what, n=1):
    s, k = re.subn(pattern, new, s, flags=re.M)
    if k != n:
        die('%s -- matched %d times, expected %d' % (what, k, n))
    say(what)
    return s

# The commands.
for c, handler in (('lmap', 'ex_map'), ('lnoremap', 'ex_map'), ('lunmap', 'ex_unmap'), ('lmapclear', 'ex_mapclear')):
    t = sub(t, r'^([ \t]*\[CMD_%s\] = \{\(char_u \*\)"%s", sizeof\("%s"\) - 1, )%s,' % (c, c, c, handler), r'\1ex_ni,',
            ':%s points at ex_ni' % c)
def bycmd(s):
    for c in ('lmap', 'lnoremap', 'lunmap', 'lmapclear'):
        s = sub(s, r'^[ \t]*case CMD_%s:\n' % c, '', 'no completion for :%s' % c)
    return s
t = in_function(t, 'set_context_by_cmdname', bycmd)

# CTRL-^: consumed, and nothing to toggle.
t = in_function(t, 'edit', lambda s: sub(drop_if(s, r'^[ \t]*if \(curbuf->b_p_iminsert == B_IMODE_LMAP\)$', 'Insert mode starting with language mappings'),
                                         r'^([ \t]*case Ctrl_HAT:\n)[ \t]*ins_ctrl_hat\(\);\n', r'\1', 'CTRL-^ in Insert mode toggling nothing'))
t = in_function(t, 'getcmdline_int', lambda s: sub(
    drop_if(s, r"^[ \t]*if \(firstc == '/' \|\| firstc == '\?' \|\| firstc == '@'\)$", 'a search line starting with language mappings'),
    r'^([ \t]*case Ctrl_HAT:\n)[ \t]*cmdline_toggle_langmap\([^\n]*\);\n', r'\1', 'CTRL-^ on the command line toggling nothing'))

t = in_function(t, 'ex_append', lambda s: drop_if(s, r'^[ \t]*if \(curbuf->b_p_iminsert == B_IMODE_LMAP\)$', ':append starting with language mappings'))
t = in_function(t, 'ins_insert', lambda s: literal(s, ' | (State & MODE_LANGMAP)', '', '<Insert> keeping the language-mapping flag', 2))

def morechars(s):
    s = drop_if(s, r'^[ \t]*if \(lang && curbuf->b_p_iminsert == B_IMODE_LMAP\)$', 'r, f and t reading through language mappings')
    s = drop_if(s, r'^[ \t]*if \(langmap_active\)$', 'r, f and t restoring after language mappings')
    return s
t = in_function(t, 'normal_cmd_get_more_chars', morechars)

t = in_function(t, 'handle_mapping', lambda s: literal(
    s, ' && ((mp->m_mode & MODE_LANGMAP) == 0 || typebuf.tb_maplen == 0)', '', 'a mapping refused only for a language mapping'))
t = in_function(t, 'vgetorpeek', lambda s: literal(
    s, '((State & (MODE_NORMAL | MODE_INSERT)) || State == MODE_LANGMAP)', '(State & (MODE_NORMAL | MODE_INSERT))',
    'the cursor placed while waiting in language-mapping state'))
t = in_function(t, 'get_map_mode', lambda s: fold_never(s, r"^[ \t]*else if \(modec == 'l'\)$", "the 'l' map mode"))
t = in_function(t, 'map_mode_to_chars', lambda s: fold_never(s, r'^[ \t]*else if \(mode & MODE_LANGMAP\)$', "listing a mapping as 'l'"))
t = in_function(t, 'win_redr_status', lambda s: drop_if(
    s, r'^[ \t]*if \(\(NameBufflen = get_keymap_str\(wp, \(char_u \*\)"<%s>", NameBuff,  PATH_MAX \)\) > 0', "the status line's <lang>"))

open(path, 'w', errors='surrogateescape').write(t)
PY

python3 tools/create_cmdidxs.py "$f" --check >/dev/null

python3 tools/dropoptions.py "$f" --local iminsert imsearch

tools/sweep.sh "$f"
python3 tools/droplocal.py "$f" b_p_iminsert b_p_imsearch
tools/sweep.sh "$f"

for g in b_p_iminsert b_p_imsearch p_iminsert p_imsearch B_IMODE_NONE B_IMODE_LMAP B_IMODE_LAST MODE_LANGMAP \
         ins_ctrl_hat cmdline_toggle_langmap set_iminsert_global set_imsearch_global did_set_iminsert did_set_imsearch \
         get_keymap_str b_im_ptr langmap_active; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  nolangmap    $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  nolangmap    no language-mapping mode, toggle or option is left"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
(cd "$d" && HOME="$d" ./vim -e -s '+set sw=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  nolangmap    the control :set sw=3 failed"; exit 1; }
for o in iminsert imsearch; do
    if (cd "$d" && HOME="$d" ./vim -e -s "+set $o?" '+q!' </dev/null >/dev/null 2>&1); then
        echo "  nolangmap    :set $o? was accepted"; exit 1
    fi
done
if (cd "$d" && HOME="$d" ./vim -e -s '+lmap a b' '+q!' </dev/null >/dev/null 2>&1); then
    echo "  nolangmap    :lmap was accepted"; exit 1
fi
printf 'x\n' > "$d/h.txt"
(cd "$d" && HOME="$d" ./vim -e -s "$(printf '+1normal! Ia\036b')" '+wq' h.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/h.txt")" = abx ] || { echo "  nolangmap    CTRL-^ in Insert mode left '$(cat "$d/h.txt")'"; exit 1; }
echo "  nolangmap    :set sw works; iminsert, imsearch and :lmap are unknown; CTRL-^ inserts nothing"

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
