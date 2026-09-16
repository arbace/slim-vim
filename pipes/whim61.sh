#!/bin/sh
# Whim phase 61 -- no window title.  See WHIM-GOAL.md.
#
# Usage: pipes/whim61.sh <work-dir>      (run from the repository root)
#
# 'title', 'titlelen', 'titleold', 'titlestring', 'icon' and 'iconstring' go, and
# with them everything that set or restored the terminal's title: maketitle() and
# its thirteen callers, need_maketitle, resettitle(), mch_settitle(),
# mch_restore_title(), set_title_defaults(), term_settitle(), the X11 title and
# icon probes, and the title-stack push at startup and pop at exit.  The editor
# no longer writes to the terminal's title at all.  The t_ts, t_fs, t_ST and t_RT
# terminal codes stay: the terminal codes were kept as a whole.
#
# THE DELTA: none the harnesses record.  The probes check the six are unknown.
set -eu

work=${1:?usage: whim61.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 - "$f" <<'PY'
TAG = 'notitle'
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

for fn in ('showruler', 'redraw_cmd', 'ui_focus_change', 'main_loop'):
    t = in_function(t, fn, lambda s, fn=fn: drop_if(s, r'^[ \t]*if \(need_maketitle\)$', '%s updating the title' % fn))
for fn in ('enter_buffer', 'buf_name_changed', 'do_ecmd', 'set_termname', 'set_shellsize_inner', 'win_enter_ext'):
    t = in_function(t, fn, lambda s, fn=fn: sub(s, r'^[ \t]*maketitle\(\);\n', '', '%s updating the title' % fn))
def exedit(s):
    s = drop_if(s, r'^[ \t]*if \(n != curwin->w_arg_idx_invalid\)$', ':edit updating the title when the argument index moved')
    s = sub(s, r'^[ \t]*n = curwin->w_arg_idx_invalid;\n', '', ':edit remembering the argument index for the title')
    return s
t = in_function(t, 'do_exedit', exedit)
# n has one other use in do_exedit(): saving and restoring readonlymode around
# :view.  So after the title's assignment and test go, exactly three mentions are
# left -- the declaration, the save and the restore.  Any other count is a use of n
# nobody accounted for.
sp = cutil.find_definition(t, 'do_exedit')
k = len(re.findall(r'\bn\b', t[sp[0]:sp[1]]))
if k != 3:
    die("do_exedit mentions n %d times after the title went, expected 3 (declaration, readonlymode save and restore)" % k)
def stop(s):
    s = sub(s, r'^[ \t]*mch_restore_title\( \(SAVE_RESTORE_TITLE \| SAVE_RESTORE_ICON\) \);\n', '', ':stop restoring the title')
    s = sub(s, r'^[ \t]*maketitle\(\);\n[ \t]*resettitle\(\);\n', '', ':stop setting the title again')
    return s
t = in_function(t, 'ex_stop', stop)
def mexit(s):
    s = sub(s, r'^[ \t]*mch_restore_title\( \(SAVE_RESTORE_TITLE \| SAVE_RESTORE_ICON\) \);\n', '', 'exit restoring the title')
    s = sub(s, r'^[ \t]*term_pop_title\( \(SAVE_RESTORE_TITLE \| SAVE_RESTORE_ICON\) \);\n', '', "exit popping the terminal's title stack")
    return s
t = in_function(t, 'mch_exit', mexit)
t = in_function(t, 'vim_main2', lambda s: sub(s, r'^[ \t]*term_push_title\( \(SAVE_RESTORE_TITLE \| SAVE_RESTORE_ICON\) \);\n', '', "startup pushing the terminal's title stack"))
t = in_function(t, 'clear_termoptions', lambda s: sub(s, r'^[ \t]*mch_restore_title\( \(SAVE_RESTORE_TITLE \| SAVE_RESTORE_ICON\) \);\n', '', 'changing terminal restoring the title'))
t = in_function(t, 'value_changed', lambda s: sub(s, r'^[ \t]*mch_restore_title\(last == &lasttitle \? SAVE_RESTORE_TITLE : SAVE_RESTORE_ICON\);\n', '', 'a cleared value restoring the title'))
t = in_function(t, 'set_init_3', lambda s: sub(s, r'^[ \t]*set_title_defaults\(\);\n', '', "startup choosing 'title' and 'icon' defaults"))
# Six: buf_write(), changed_internal(), unchanged(), redraw_titles(), and two that
# the sweep takes anyway -- maketitle()'s own early return and did_set_titlelen().
t = sub(t, r'^[ \t]*need_maketitle = TRUE;\n', '', 'changes asking for a title update', 6)

open(path, 'w', errors='surrogateescape').write(t)
PY

python3 tools/dropoptions.py "$f" title titlelen titleold titlestring icon iconstring

tools/sweep.sh "$f"

for g in p_title p_titlelen p_titleold p_titlestring p_icon p_iconstring maketitle resettitle mch_settitle mch_restore_title \
         set_title_defaults need_maketitle lasttitle lasticon oldtitle oldicon term_settitle term_push_title term_pop_title; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  notitle      $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  notitle      nothing sets, restores, pushes or pops the terminal's title"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
(cd "$d" && HOME="$d" ./vim -e -s '+set sw=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  notitle      the control :set sw=3 failed"; exit 1; }
for o in title titlelen titleold titlestring icon iconstring; do
    if (cd "$d" && HOME="$d" ./vim -e -s "+set $o?" '+q!' </dev/null >/dev/null 2>&1); then
        echo "  notitle      :set $o? was accepted"; exit 1
    fi
done
echo "  notitle      :set sw works; the six title and icon options are unknown"

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
