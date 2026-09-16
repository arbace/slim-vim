#!/bin/sh
# Whim phase 59 -- no command-line completion.  See WHIM-GOAL.md.
#
# Usage: tools/whim59.sh <work-dir>      (run from the repository root)
#
# The command line no longer completes anything.  In getcmdline_int() the
# 'wildchar' and 'wildcharm' keys, S-Tab, CTRL-D (list), CTRL-A (insert all),
# CTRL-L (longest match) and CTRL-N/CTRL-P over matches go; each of those keys is
# now an ordinary character, and CTRL-N/CTRL-P browse history as they did with no
# matches.  CTRL-L still adds a character to an incremental search.
#
# What completion shared with filename expansion stays: expand_filename() ->
# ExpandOne() with EXPAND_FILES, and the argument list through expand_wildcards().  So ExpandFromContext() keeps its file branch and loses the
# rest -- options, mappings, buffers, highlight groups, ++opt, every command's
# argument completion -- and ExpandOne() keeps the one mode its last caller asks
# for.  The sweep takes set_one_cmd_context() and everything under it.
#
# The six wild* options go: 'wildchar', 'wildcharm', 'wildmode', 'wildoptions',
# 'wildignore' and 'wildignorecase'.  The last two were read by globbing too, and
# fold as empty and off.
#
# THE DELTA: none the harnesses record.  The probes check the options are unknown
# and that `:e` still edits a named file.
set -eu

work=${1:?usage: whim59.sh <work-dir>}
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
    sys.exit('  nocompletion ' + msg)

def say(what):
    print('  nocompletion ' + what)

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

def fold_never(s, pattern, what):
    count(s, pattern, 1, what)
    try:
        s = cutil.fold_never(s, pattern, 1, re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e))
    say(what)
    return s

def fold_always(s, pattern, what):
    count(s, pattern, 1, what)
    try:
        s = cutil.fold_always(s, pattern, 1, re.M)
    except ValueError as e:
        die('%s -- %s' % (what, e))
    say(what)
    return s

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

KEY = lambda a, b: r"\(-\(\('%s'\) \+ \(\(int\)\('%s'\) << 8\)\)\)" % (a, b)
KEX = lambda k: r'\(-\(\(KS_EXTRA\) \+ \(\(int\)\(%s\) << 8\)\)\)' % k

def cmdline(s):
    s = drop_if(s, r'^[ \t]*if \(ccline\.cmdbuff_replaced && xpc\.xp_numfiles > 0\)$', 'a replaced command line freeing its matches')
    s = drop_if(s, r'^[ \t]*if \(c == [ \t]*%s[ \t]*&& did_hist_navigate\)$' % KEX('KE_WILD'), 'a wildcard trigger after history navigation')
    s = sub(s, r'^[ \t]*did_hist_navigate = TRUE;\n', '', 'history navigation remembered for the wildcard trigger')
    s = drop_if(s, r'^[ \t]*if \(c != p_wc && c == [ \t]*%s[ \t]*&& xpc\.xp_numfiles > 0\)$' % KEY('k', 'B'), 'S-Tab stepping back through matches')
    s = sub(s, r'^[ \t]*int key_is_wc = [^\n]*;\n', '', "the 'wildchar' key test")
    s = drop_if(s, r'^[ \t]*if \(\(did_wild_list\) && !key_is_wc && xpc\.xp_numfiles > 0\)$', 'CTRL-E and CTRL-Y over a match list')
    s = drop_if(s, r'^[ \t]*if \(\(c == ESC \|\| c == Ctrl_C\) && \(wim_flags\[0\] & WIM_LIST\)\)$', "leaving a 'wildmode' list clearing 'hlsearch'")
    s = sub(s, r'^[ \t]*end_wildmenu = \([^\n]*\);\n', '', 'deciding the match list ends')
    s = drop_if(s, r'^[ \t]*if \(end_wildmenu\)$', 'ending the match list')
    s = drop_if(s, r'^[ \t]*if \(\(c == p_wc && !gotesc && KeyTyped\) \|\| c == p_wcm \|\| c == [ \t]*%s[ \t]*\)$' % KEX('KE_WILD'),
                "completing on 'wildchar', 'wildcharm' or the wildcard trigger")
    s = drop_if(s, r'^[ \t]*if \(c == [ \t]*%s[ \t]*&& KeyTyped\)$' % KEY('k', 'B'), 'S-Tab completing backwards')
    s = sub(s, r'^[ \t]*case Ctrl_D:\n[ \t]*if \(showmatches\(&xpc, TRUE\) == EXPAND_NOTHING\)\n[ \t]*\{\n[ \t]*break;\n[ \t]*\}\n\n?[ \t]*redrawcmd\(\);\n[ \t]*continue;\n\n?',
            '', 'CTRL-D listing matches')
    s = sub(s, r'^[ \t]*case Ctrl_A:\n[ \t]*if \(nextwild\(&xpc, WILD_ALL, 0, firstc != \'@\'\) == FAIL\)\n[ \t]*\{\n[ \t]*break;\n[ \t]*\}\n[ \t]*xpc\.xp_context = EXPAND_NOTHING;\n[ \t]*did_wild_list = FALSE;\n[ \t]*goto cmdline_changed;\n\n?',
            '', 'CTRL-A inserting every match')
    s = sub(s, r'^([ \t]*)if \(nextwild\(&xpc, WILD_LONGEST, 0, firstc != \'@\'\) == FAIL\)\n[ \t]*\{\n[ \t]*break;\n[ \t]*\}\n[ \t]*goto cmdline_changed;\n',
            r'\1break;\n', 'CTRL-L completing the longest match')
    s = drop_if(s, r'^[ \t]*if \(xpc\.xp_numfiles > 0\)$', 'CTRL-N and CTRL-P stepping through matches')
    s = sub(s, r'^[ \t]*did_wild_list = FALSE;\n[ \t]*wim_index = 0;\n', '', 'leaving the command line resetting the match list')
    s = literal(s, 'may_trigger_safestate(xpc.xp_numfiles <= 0);', 'may_trigger_safestate(TRUE);', 'SafeState not waiting on a match list')
    s = literal(s, 'if (xpc.xp_context == EXPAND_NOTHING && (KeyTyped || vpeekc() == NUL))', 'if (KeyTyped || vpeekc() == NUL)',
                'incremental search not waiting on a completion context')
    return s
t = in_function(t, 'getcmdline_int', cmdline)

# Each options[] row names a callback that completes its value, called only by
# :set completion, which is gone -- but the table keeps them reachable, and with
# them ExpandGeneric() and the fuzzy matcher.  The row's callback becomes NULL.
a = re.search(r'^[ \t]*\{"ambiwidth",', t, re.M).start()
z = t.index('\n};', a)
table, k = re.subn(r'\bexpand_set_\w+(\s*,)', r'NULL\1', t[a:z])
if k < 20:
    die('options[] names %d value-completion callbacks, expected many' % k)
t = t[:a] + table + t[z:]
say('options[] no longer names a value-completion callback (%d rows)' % k)

def fromctx(s):
    s = sub(s, r'^[ \t]*\*matches = \(char_u \*\*\)"";\n.*?^[ \t]*return ret;\n', '', 'every completion context but files', flags_dotall=True) if False else s
    m = re.search(r'^    \*matches = \(char_u \*\*\)"";\n', s, re.M)
    z = s.rfind('\n    return ret;\n')
    if not m or z < 0:
        die('ExpandFromContext -- the non-file contexts were not found')
    s = s[:m.start()] + s[z + len('\n    return ret;\n'):]
    say('every completion context but files')
    s = fold_always(s, r'^[ \t]*if \(xp->xp_context == EXPAND_FILES \|\| xp->xp_context == EXPAND_DIRECTORIES \|\| xp->xp_context == EXPAND_FILES_IN_PATH \|\| xp->xp_context == EXPAND_FINDFUNC \|\| xp->xp_context == EXPAND_DIRS_IN_CDPATH\)$',
                    'file expansion is the only context')
    return s
t = in_function(t, 'ExpandFromContext', fromctx)

def expone(s):
    s = fold_never(s, r'^[ \t]*if \(mode == WILD_NEXT \|\| mode == WILD_PREV \|\| mode == WILD_PAGEUP \|\| mode == WILD_PAGEDOWN\)$', 'ExpandOne stepping through matches')
    s = fold_never(s, r'^[ \t]*if \(mode == WILD_CANCEL\)$', 'ExpandOne cancelling or applying a match')
    s = fold_never(s, r'^[ \t]*if \(mode == WILD_FREE\)$', 'ExpandOne only freeing')
    s = fold_never(s, r'^[ \t]*if \(mode == WILD_LONGEST && xp->xp_numfiles > 0\)$', 'ExpandOne finding the longest match')
    s = fold_never(s, r'^[ \t]*if \(mode == WILD_ALL && xp->xp_numfiles > 0 && !got_int\)$', 'ExpandOne joining every match')
    s = fold_always(s, r'^[ \t]*if \(mode == WILD_EXPAND_FREE \|\| mode == WILD_ALL\)$', 'ExpandOne always cleaning up after expanding')
    return s
t = in_function(t, 'ExpandOne', expone)

t = in_function(t, 'didset_options2', lambda s: sub(s, r'^[ \t]*check_opt_wim\(\);\n\n?', '', "startup parsing 'wildmode' into flags nothing reads"))
t = in_function(t, 'expand_filename', lambda s: drop_if(s, r'^[ \t]*if \(p_wic\)$', "'wildignorecase' in filename globbing"))
t = in_function(t, 'expand_wildcards', lambda s: drop_if(s, r'^[ \t]*if \(\*p_wig\)$', "'wildignore' in filename globbing"))
t = in_function(t, 'do_set_option_numeric', lambda s: fold_never(s, r'^[ \t]*else if \(\(\(long \*\)varp == &p_wc \|\| \(long \*\)varp == &p_wcm\)', ":set wc= accepting a key name"))
t = in_function(t, 'wc_use_keyname', lambda s: fold_never(s, r'^[ \t]*if \(\(\(long \*\)varp == &p_wc\) \|\| \(\(long \*\)varp == &p_wcm\)\)$', ":set wc? showing a key name"))

open(path, 'w', errors='surrogateescape').write(t)
PY

python3 tools/dropoptions.py "$f" wildchar wildcharm wildmode wildoptions wildignore wildignorecase

tools/sweep.sh "$f"

# ExpandOne's only caller must be expand_filename() once the sweep has taken the
# dead ones -- nextwild(), showmatches() and the rest -- or a mode folded above is
# still asked for.  Before the sweep they are all still there, which a first
# version of this check found out by failing.
callers=$(grep -cE '\bExpandOne\(' "$f" || true)
[ "$callers" = 3 ] || { echo "  nocompletion ExpandOne is named $callers times, expected 3 (prototype, definition, expand_filename)"; grep -nE '\bExpandOne\(' "$f" | cut -c1-120; exit 1; }


for g in p_wc p_wcm p_wim p_wop p_wig p_wic wim_flags nextwild showmatches cmdline_wildchar_complete set_expand_context \
         set_one_cmd_context ExpandSettings ExpandMappings ExpandBufnames expand_argopt get_next_or_prev_match \
         find_longest_match did_wild_list check_opt_wim; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  nocompletion $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
echo "  nocompletion no completion key, context, match list or wild* option is left"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"
(cd "$d" && HOME="$d" ./vim -e -s '+set sw=3' '+q!' </dev/null >/dev/null 2>&1) || { echo "  nocompletion the control :set sw=3 failed"; exit 1; }
for o in wildchar wildcharm wildmode wildoptions wildignore wildignorecase; do
    if (cd "$d" && HOME="$d" ./vim -e -s "+set $o?" '+q!' </dev/null >/dev/null 2>&1); then
        echo "  nocompletion :set $o? was accepted"; exit 1
    fi
done
# :e still takes a file name.  NOT a wildcard: `:e onlyo*` already failed to
# expand in the previous phase's binary -- it wrote a file named `onlyo*` -- so a
# probe that demanded expansion checked something this phase never had.
printf 'x\n' > "$d/onlyone.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+e onlyone.txt' '+1s/x/y/' '+w' '+q!' </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/onlyone.txt")" = y ] || { echo "  nocompletion :e onlyone.txt did not edit it: '$(cat "$d/onlyone.txt")'"; exit 1; }
echo "  nocompletion :set sw works; the wild* options are unknown; :e still edits a named file"

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
