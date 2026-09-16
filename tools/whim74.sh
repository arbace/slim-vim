#!/bin/sh
# Whim phase 74 -- no file marks.  See WHIM-GOAL.md.
#
# Usage: tools/whim74.sh <work-dir>      (run from the repository root)
#
# THIS IS THE PHASE THAT WAS ABANDONED AS 70 AND IS NOW REDONE PROPERLY.  The first
# attempt died three times on patterns transcribed from truncated views -- the
# `|| to < from` tail, clrallmarks' `static int i = -1` guard over 26 + 1, and four
# unenumerated adjust sites -- and, worse, its probes MEASURED NOTHING, because a
# mark name like 'A carries a quote that broke the shell quoting so the key was never
# pressed.  Every site below was read verbatim with cat -A first, and every probe was
# calibrated against q73 before being trusted.
#
# WHAT GOES: namedfm[26 + EXTRA_MARKS], which is BOTH the uppercase A-Z file marks
# and the numbered 0-9 marks -- one array, one set of code paths, so they cannot be
# separated.  With one buffer the numbered marks could never be set anyway: viminfo
# is long gone, so they were a store nothing could write.
#
#   mA .. mZ   'A .. 'Z   `A .. `Z   '0 .. '9
#   the cross-file jump: getmark_buf_fnum's arm was the ONLY caller of
#   buflist_getfile(), and of fname2fnum() -- itself already an empty body from
#   phase 70, folded there precisely because the file marks were a separate cut.
#
# WHAT STAYS: the lowercase marks a-z in buf->b_namedm[], and every special mark --
# ' ` " ^ . [ ] < > -- none of which touch namedfm.  :marks still lists what is left
# and :delmarks still clears it; uppercase and digits become "invalid argument".
# fmark_T STAYS: struct taggy embeds it, so the tag stack depends on it.  Only
# xfmark_T, which exists to bolt a filename onto a mark, goes.
#
# SCOPE EVERY EDIT BY FUNCTION.  do_join() has a PARAMETER named `setmark`, so a
# global rename or an unscoped pattern would corrupt it -- the b_next lesson from
# phase 71 in a new costume.
#
# THE DELTA: none expected.  :marks and :delmarks keep their exit status and write
# nothing to stderr for the arguments exsweep uses, and an exsweep row is
# `exit= left= err=`.  Declared empty and left for whimdelta.sh to correct.
set -eu

work=${1:?usage: whim74.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 - "$f" <<'PY'
TAG = 'nofmark'
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

def literal(s, old, new, what, n=1):
    k = s.count(old)
    if k != n:
        die('%s -- occurs %d times, expected %d' % (what, k, n))
    say(what)
    return s.replace(old, new)

def lines(text, pattern, what, n=1):
    rx = re.compile(r'^[ \t]*' + pattern + r'[ \t]*\n', re.M)
    k = len(rx.findall(text))
    if k != n:
        die('%s -- %d lines match, expected %d' % (what, k, n))
    say(what)
    return rx.sub('', text)

def replace_body(text, name, new_body, what):
    def edit(s):
        return s[:s.index('{\n') + 2] + new_body + '}\n'
    out = in_function(text, name, edit)
    say(what)
    return out

def drop_def(text, name, what):
    out, ok = cutil.delete_definition(text, name)
    if not ok:
        die('%s -- %s is not defined' % (what, name))
    say(what)
    return out

def drop_blocks(text, fn, anchor_re, what, n=1):
    """Delete a brace-matched block, anchored on the line that opens it, n times.

    Brace matching rather than a line pattern, because these bodies are
    macro-expanded one-liners hundreds of characters wide -- transcribing them is
    exactly what killed this phase's first attempt.
    """
    def edit(s):
        rx = re.compile(anchor_re, re.M)
        k = len(rx.findall(s))
        if k != n:
            die('%s -- the anchor matches %d times, expected %d' % (what, k, n))
        out = s
        for _ in range(n):
            m = rx.search(out)
            b = cutil.blank(out)
            k0 = out.rfind('\n', 0, m.start()) + 1
            o = out.index('{', m.start())
            c = cutil.match(out, o, b)
            if c < 0:
                die('%s -- unbalanced block' % what)
            out = out[:k0] + out[out.index('\n', c) + 1:]
        say(what)
        return out
    return in_function(text, fn, edit)

def fold_never(text, fn, pattern, what, n=1):
    def edit(s):
        try:
            return cutil.fold_never(s, pattern, n, re.M)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    out = in_function(text, fn, edit)
    say(what)
    return out

def drop_if(text, fn, pattern, what, n=1):
    def edit(s):
        try:
            return cutil.drop_if(s, pattern, n, re.M)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    out = in_function(text, fn, edit)
    say(what)
    return out

# The two arms are spelled identically apart from the leading keyword.  Written as a
# regex against the read bytes, never as a heredoc literal: the line carries doubled
# spaces around || that are easy to lose.
ARM = (r"\( \(\(unsigned\)\(c\) - 'A' < 26\)  \|\|  \(\(unsigned\)\(c\) - '0' < 10\) \)$")

# ---- 1. reading an uppercase or numbered mark -----------------------------------
# The arm is the last in an else-if chain, so removing it leaves the chain intact and
# posp stays NULL -- which is exactly what check_mark() reports as "E20: Mark not
# set", the same answer an unset lowercase mark already gives.  Measured on q73: an
# unset mark leaves the file untouched.
t = fold_never(t, 'getmark_buf_fnum', r'^[ \t]*else if ' + ARM,
               'reading an uppercase or numbered mark')

# ---- 2. setting one --------------------------------------------------------------
# A plain if followed by `return FAIL;`, not by an else, so dropping it falls through
# to the failure that nv_mark turns into a beep.
t = drop_if(t, 'setmark_pos', r'^[ \t]*if ' + ARM,
            'setting an uppercase or numbered mark')

# ---- 3. clearing them ------------------------------------------------------------
# The `static int i = -1` guard ran the file-mark initialisation exactly once, on the
# first call, and the static existed only for that.  Its `26 + 1` bound -- not
# 26 + EXTRA_MARKS -- is the detail the abandoned attempt kept getting wrong.
t = replace_body(t, 'clrallmarks', '''    int         i;

    for (i = 0; i <  ('z' - 'a' + 1) ; i++)
    {
        buf->b_namedm[i].lnum = 0;
    }
    buf->b_op_start.lnum = 0;
    buf->b_op_end.lnum = 0;
    buf->b_last_cursor.lnum = 1;
    buf->b_last_cursor.col = 0;
    buf->b_last_cursor.coladd = 0;
    buf->b_last_insert.lnum = 0;
    buf->b_last_change.lnum = 0;
    buf->b_changelistlen = 0;
''', 'clrallmarks initialising the file marks once')

# ---- 4. listing them -------------------------------------------------------------
t = drop_blocks(t, 'ex_marks',
                r"^[ \t]*for \(i = 0; i <  \('z' - 'a' \+ 1\)  \+ EXTRA_MARKS; \+\+i\)$",
                ':marks listing the file marks')

# ---- 5. deleting them ------------------------------------------------------------
# Rewritten whole rather than patched: the branch interleaves lower/digit/upper three
# ways, and the `|| to < from` tail is one of the three patterns the first attempt
# could never match.  Lowercase keeps its range form; uppercase and digits fall to
# the default and report an invalid argument.
t = replace_body(t, 'ex_delmarks', '''    char_u      *p;
    int from;
    int to;
    int         i;

    if (*eap->arg == NUL && eap->forceit)
    {
        clrallmarks(curbuf);
    }
    else if (eap->forceit)
    {
        emsg(_(e_invalid_argument));
    }
    else if (*eap->arg == NUL)
    {
        emsg(_(e_argument_required));
    }
    else
    {
        for (p = eap->arg; *p != NUL; ++p)
        {
            if ( ((unsigned)(*p) - 'a' < 26) )
            {
                if (p[1] == '-')
                {
                    from = *p;
                    to = p[2];
                    if (! ((unsigned)(p[2]) - 'a' < 26)  || to < from)
                    {
                        semsg(_(e_invalid_argument_str), p);
                        return;
                    }
                    p += 2;
                }
                else
                {
                    from = to = *p;
                }

                for (i = from; i <= to; ++i)
                {
                    curbuf->b_namedm[i - 'a'].lnum = 0;
                }
            }
            else
            {
                switch (*p)
                {
                    case '"':
                        curbuf->b_last_cursor.lnum = 0;
                        break;
                    case '^':
                        curbuf->b_last_insert.lnum = 0;
                        break;
                    case '.':
                        curbuf->b_last_change.lnum = 0;
                        break;
                    case '[':
                        curbuf->b_op_start.lnum    = 0;
                        break;
                    case ']':
                        curbuf->b_op_end.lnum      = 0;
                        break;
                    case '<':
                        curbuf->b_visual.vi_start.lnum = 0;
                        break;
                    case '>':
                        curbuf->b_visual.vi_end.lnum   = 0;
                        break;
                    case ' ':
                        break;
                    default:
                        semsg(_(e_invalid_argument_str), p);
                              return;
                }
            }
        }
    }
''', ':delmarks clearing an uppercase or numbered mark')

# ---- 6. adjusting them when lines and columns move --------------------------------
# Four sites, two per function: a guarded block inside the lowercase loop, and a whole
# second loop over the numbered range.  These are the "four unenumerated adjust sites"
# the abandoned attempt never listed.  Brace-matched, because each body is one
# macro-expanded line of several hundred characters.
for fn in ('mark_adjust_internal', 'mark_col_adjust'):
    t = drop_blocks(t, fn, r'^[ \t]*if \(namedfm\[i\]\.fmark\.fnum == fnum\)$',
                    'adjusting the file marks in %s' % fn, 2)
    t = drop_blocks(t, fn,
                    r"^[ \t]*for \(i =  \('z' - 'a' \+ 1\) ; i <  \('z' - 'a' \+ 1\)  \+ EXTRA_MARKS; i\+\+\)$",
                    'and the loop over the numbered marks in %s' % fn)

# ---- 7. matching a reopened file back to its marks --------------------------------
# fmarks_check_names existed to reattach a file mark to a buffer by name; with no file
# marks there is nothing to reattach.  Its two callers go with it.
t = lines(t, r'fmarks_check_names\(buf\);', 'the two calls that rematched file marks', 2)
t = drop_def(t, 'fmarks_check_names', 'fmarks_check_names, which had nothing to match')

# fname2fnum is already an empty body -- phase 70 folded it so that :e could not wipe
# the buffer being edited -- and its last caller went in step 1.
t = drop_def(t, 'fname2fnum', 'fname2fnum, folded empty in phase 70 and now unreachable')

# ---- 8. the store itself ----------------------------------------------------------
t = lines(t, r"static xfmark_T namedfm\[ \('z' - 'a' \+ 1\)  \+ EXTRA_MARKS\];", 'namedfm')
t = literal(t, '''typedef struct xfilemark
{
    fmark_T     fmark;
    char_u      *fname;
} xfmark_T;

''', '', 'xfmark_T, a mark with a filename bolted on')
t = lines(t, r'enum \{ EXTRA_MARKS = 10 \};', 'the numbered-mark count')

open(path, 'w', errors='surrogateescape').write(t)
PY

python3 tools/create_cmdidxs.py "$f" --check >/dev/null

tools/sweep.sh "$f"

# The file marks are gone, and so is everything that only existed to serve them.
for g in namedfm xfmark_T EXTRA_MARKS fname2fnum fmarks_check_names fmarks_check_one \
         fm_getname buflist_getfile; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    [ "$n" = 0 ] || { echo "  nofmark      $g still has $n mentions"; exit 1; }
done
# fmark_T STAYS: struct taggy embeds it, so the tag stack depends on it.
grep -qE '\bfmark_T\b' "$f" || { echo "  nofmark      fmark_T went -- the tag stack embeds it"; exit 1; }
grep -qE 'fmark_T[ \t]+fmark;' "$f" || { echo "  nofmark      struct taggy lost its fmark"; exit 1; }
# and the marks that are NOT file marks must all survive
for g in b_namedm b_last_cursor b_last_insert b_last_change b_op_start b_op_end \
         w_pcmark w_prev_pcmark setpcmark getmark setmark setmark_pos check_mark \
         clrallmarks mark_adjust_internal mark_col_adjust ex_marks ex_delmarks; do
    grep -qE "\\b$g\\b" "$f" || { echo "  nofmark      $g went -- that was never a file mark"; exit 1; }
done
# do_join's PARAMETER named setmark must be untouched -- an unscoped edit would have
# eaten it, which is the b_next mistake in another costume.
grep -qE 'do_join\(long[^)]*int[ \t]+setmark\)' "$f" || { echo "  nofmark      do_join lost its setmark parameter"; exit 1; }
echo "  nofmark      no file marks; lowercase, the special marks and the tag stack intact"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# LOAD FIRST.
printf 'a\nb\nc\n' > "$d/t.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+$' '+s/^/LAST /' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/t.txt")" = 'a|b|LAST c|' ] || { echo "  nofmark      the file did not load: '$(tr '\n' '|' < "$d/t.txt")'"; exit 1; }

printf 'one\ntwo\nthree\n' > "$d/e.txt"
(cd "$d" && HOME="$d" ./vim -e -s '+2' '+normal! dd' '+wq' e.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/e.txt")" = 'one|three|' ] || { echo "  nofmark      editing broke: '$(tr '\n' '|' < "$d/e.txt")'"; exit 1; }

# THE DISCRIMINATOR, and the reason this phase failed the first time.  The mark name
# carries a quote, so the vim text is double-quoted at the shell and the quote never
# reaches a shell metacharacter position.  Both halves were calibrated on q73, where
# lowercase gives K1|K2-kept|K3| and uppercase gives U1-up|U2|U3| -- so the uppercase
# case CHANGES here, which is what makes it evidence rather than decoration.
printf 'K1\nK2\nK3\n' > "$d/lo.txt"
(cd "$d" && HOME="$d" ./vim -e -s "+normal! 2Gmb" "+normal! 3G" "+normal! 'bA-kept" "+wq" lo.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/lo.txt")" = 'K1|K2-kept|K3|' ] || { echo "  nofmark      a lowercase mark stopped working: '$(tr '\n' '|' < "$d/lo.txt")'"; exit 1; }

printf 'U1\nU2\nU3\n' > "$d/up.txt"
(cd "$d" && HOME="$d" ./vim -e -s "+normal! 1GmA" "+normal! 3G" "+normal! 'AA-up" "+wq" up.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/up.txt")" = 'U1|U2|U3|' ] || { echo "  nofmark      an uppercase mark still works: '$(tr '\n' '|' < "$d/up.txt")'"; exit 1; }

# a backtick mark too, the other key that reaches getmark
printf 'B1\nB2\nB3\n' > "$d/bt.txt"
(cd "$d" && HOME="$d" ./vim -e -s "+normal! 2Gmc" "+normal! 3G" '+normal! `cA-bt' "+wq" bt.txt </dev/null >/dev/null 2>&1) || true
[ "$(tr '\n' '|' < "$d/bt.txt")" = 'B1|B2-bt|B3|' ] || { echo "  nofmark      a backtick mark stopped working: '$(tr '\n' '|' < "$d/bt.txt")'"; exit 1; }

# :marks and :delmarks must still run.  NOT discriminators -- both write the file
# either way and neither reaches stderr -- so they are no-crash checks only.
printf 'M1\n' > "$d/mk.txt"
(cd "$d" && HOME="$d" ./vim -e -s "+normal! 1Gma" '+marks' "+normal! A-mk" '+wq' mk.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/mk.txt")" = 'M1-mk' ] || { echo "  nofmark      :marks broke the session: $(cat "$d/mk.txt")"; exit 1; }
printf 'D1\n' > "$d/dm.txt"
(cd "$d" && HOME="$d" ./vim -e -s "+normal! 1Gma" '+delmarks a' "+normal! A-dm" '+wq' dm.txt </dev/null >/dev/null 2>&1) || true
[ "$(cat "$d/dm.txt")" = 'D1-dm' ] || { echo "  nofmark      :delmarks broke the session: $(cat "$d/dm.txt")"; exit 1; }
echo "  nofmark      lowercase and backtick marks work; uppercase is unset; :marks and :delmarks run"
python3 tools/arrowcheck.py "$work/whim-vim"

# --- the delta, cumulative --------------------------------------------------
tools/whimdelta.sh "$work/whim-vim" "$f" --term-moved --cases bomb_on,filter,read_cmd,retab,sort_u,sort_n,ff_dos,binary_mode,format_gq,format_comment,open_comment \
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
