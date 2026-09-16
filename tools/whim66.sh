#!/bin/sh
# Whim phase 66 -- no sentences, paragraphs, sections, methods, #if blocks or
# comment blocks.  See WHIM-GOAL.md.
#
# Usage: tools/whim66.sh <work-dir>      (run from the repository root)
#
# One idea, cut at all three places it is reachable from:
#
#   THE MOTIONS  ( and ) by sentence, { and } by paragraph, [[ ]] [] ][ by
#       section, [m ]m [M ]M to a method's braces, [# ]# to the enclosing
#       #if/#endif, and [/ ]/ [* ]* to the enclosing C comment.  The first four
#       rows point at nv_error; the bracket ones go from nv_brackets() and
#       nv_bracket_block().
#   THE TEXT OBJECTS  is, as, ip and ap -- current_sent() and current_par().
#       A sentence you cannot move over is not one you can select either.
#   THE EX ADDRESSES  '{ '} '( ') as line addresses, which get_address() answered
#       with findpar() and findsent().
#
# After which findsent(), findpar() and startPS() have no callers at all, and the
# concept is gone from the editor rather than merely unbound.
#
# WHAT STAYS, and is checked: % and the enclosing-bracket motions [{ ]} [( ]),
# which are findmatchlimit() rather than paragraphs; the ( ) { } [ ] TEXT OBJECTS
# i( a{ i[ and so on, which are current_block(); iw/aw; and the '[ '] '< '> marks,
# which get_address() answers from stored positions.
#
# THE DELTA: none the harnesses record -- no behaviour case moves over a sentence
# or a paragraph, and no Ex command changes.  The probes check each cut key does
# nothing, that [{ and % still move, and that i{ still selects.
set -eu

work=${1:?usage: whim66.sh <work-dir>}
f="$work/whim-vim.c"

before_lines=$(grep -c '' "$f")
tools/symbols.sh "$f" .cache/symbols/before

python3 - "$f" <<'PY'
TAG = 'nopara'
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

def _last(s, pattern, f):
    m = list(re.finditer(pattern, s, re.M))[-1]
    start = s.rfind('\n', 0, m.start()) + 1
    return s[:start] + f(s[start:], pattern, 1, re.M)

def repeat(s, pattern, what, n, f):
    count(s, pattern, n, what)
    for _ in range(n):
        try:
            s = _last(s, pattern, f)
        except ValueError as e:
            die('%s -- %s' % (what, e))
    say(what if n == 1 else '%s (%d)' % (what, n))
    return s

def drop_if(s, pattern, what, n=1):
    return repeat(s, pattern, what, n, lambda x, p, c, fl: cutil.drop_if(x, p, c, fl))

def fold_never(s, pattern, what, n=1):
    return repeat(s, pattern, what, n, cutil.fold_never)

def fold_always(s, pattern, what, n=1):
    return repeat(s, pattern, what, n, cutil.fold_always)

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

def lines(s, pattern, what, n=1):
    return sub(s, r'^[ \t]*' + pattern + r'\n', '', what, n)


# ---- the motions ---------------------------------------------------------------
for key, handler, what in ((r'\(', 'nv_brace', '( by sentence'), (r'\)', 'nv_brace', ') by sentence'),
                           (r'\{', 'nv_findpar', '{ by paragraph'), (r'\}', 'nv_findpar', '} by paragraph')):
    t = sub(t, r"^([ \t]*\{'%s', )%s(, 0, [^}]*\} ,)$" % (key, handler), r'\1nv_error\2', '%s points at nv_error' % what)

t = in_function(t, 'nv_brackets', lambda s: fold_never(
    s, r"^[ \t]*else if \(cap->nchar == '\[' \|\| cap->nchar == '\]'\)$", '[[ ]] [] ][ by section'))

# [{ ]} [( ]) stay: they are findmatchlimit(), not a paragraph.  What goes from the
# dispatch set is * / # m and M.
t = literal(t, 'vim_strchr((char_u *)"{(*/#mM", cap->nchar)', 'vim_strchr((char_u *)"{(", cap->nchar)',
            '[ no longer taking a comment, #if or method')
t = literal(t, 'vim_strchr((char_u *)"})*/#mM", cap->nchar)', 'vim_strchr((char_u *)"})", cap->nchar)',
            '] no longer taking a comment, #if or method')

def block(s):
    s = drop_if(s, r"^[ \t]*if \(cap->nchar == '\*'\)$", '[* and ]* spelled as [/ and ]/')
    s = fold_always(s, r"^[ \t]*if \(cap->nchar != 'm' && cap->nchar != 'M'\)$", 'a miss beeping, which only a method did not')
    # The SAME `if (nchar == 'm' || nchar == 'M')` line appears twice: the head that
    # picks the character to match, and the half that walks out to the method.  The
    # counted helpers above cannot express "the second of two" -- they die on any
    # count but the one given -- so the walk-out is cut from a slice that starts at
    # it, and only then is the head the single match the counted fold wants.
    METHOD = r"^[ \t]*if \(cap->nchar == 'm' \|\| cap->nchar == 'M'\)$"
    hits = list(re.finditer(METHOD, s, re.M))
    if len(hits) != 2:
        die('nv_bracket_block -- the method test matched %d times, expected 2' % len(hits))
    cut = s.rfind('\n', 0, hits[1].start()) + 1
    try:
        s = s[:cut] + cutil.drop_if(s[cut:], METHOD, 1, re.M)
    except ValueError as e:
        die('walking out to a method start or end -- %s' % e)
    say('walking out to a method start or end')
    s = fold_never(s, METHOD, "a method's braces choosing the character to match")
    # The walk-out was prev_pos's only reader.  gcc says "set but not used", which
    # deadsweep.py does not handle -- it deletes unused variables, not written ones --
    # so the declaration and both writes go here.  `c` is a plain unused variable
    # once the walk-out's gchar_cursor() goes, and the sweep takes that itself.
    s = lines(s, r'pos_T[ \t]+prev_pos;', 'nv_bracket_block declaring prev_pos')
    s = lines(s, r'prev_pos\.lnum = 0;', 'the previous match, which only a method walk-out read')
    s = lines(s, r'prev_pos = new_pos;', 'remembering the previous match')
    return s
t = in_function(t, 'nv_bracket_block', block)

# ---- the text objects ----------------------------------------------------------
def obj(s):
    s = sub(s, r"^[ \t]*case 'p':\n[ \t]*flag = current_par\(cap->oap, cap->count1, include, 'p'\);\n[ \t]*break;\n", '',
            'ip and ap, the paragraph objects')
    s = sub(s, r"^[ \t]*case 's':\n[ \t]*flag = current_sent\(cap->oap, cap->count1, include\);\n[ \t]*break;\n", '',
            'is and as, the sentence objects')
    return s
t = in_function(t, 'nv_object', obj)

# ---- the Ex addresses ----------------------------------------------------------
t = fold_never(t, r"^[ \t]*else if \(c == '\{' \|\| c == '\}'\)$", "'{ and '} as line addresses")
t = fold_never(t, r"^[ \t]*else if \(c == '\(' \|\| c == '\)'\)$", "'( and ') as line addresses")

open(path, 'w', errors='surrogateescape').write(t)
PY

python3 tools/create_cmdidxs.py "$f" --check >/dev/null

tools/sweep.sh "$f"

for g in findsent findpar startPS current_sent current_par nv_brace nv_findpar; do
    n=$(grep -cE -- "\\b$g\\b" "$f" || true)
    if [ "$n" != 0 ]; then
        echo "  nopara       $g still has $n mentions after the sweep"
        grep -nE -- "\\b$g\\b" "$f" | head -3 | sed 's/^/               /' | cut -c1-100
        exit 1
    fi
done
for g in findmatchlimit nv_bracket_block current_block current_word current_quote nv_percent getnextmark nv_brackets; do
    grep -qE "\\b$g\\b" "$f" || { echo "  nopara       $g went too -- it was not the paragraph's"; exit 1; }
done
echo "  nopara       no sentence, paragraph or section is left; brackets and words are"

tools/phasecheck.sh "$work" "$f" .cache/symbols/before

tools/phasebuild.sh "$work" "$before_lines"

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cp "$work/whim-vim" "$d/vim"

# Each cut key beeps, and a beep abandons the rest of a :normal! sequence -- so the
# ix never runs and the file is untouched.  The control below proves ix would.
sample() { printf 'One two. Three four.\n\nvoid f(void)\n{\n    if (x)\n    {\n        y;\n    }\n}\n#if A\n#endif\n' > "$d/t.txt"; }
for k in ')ix' '(ix' '}ix' '{ix' ']]ix' '[[ix' '[mix' ']mix' '[#ix' '[/ix' 'dapix' 'disix'; do
    sample
    (cd "$d" && HOME="$d" ./vim -e -s '+5' "+normal! $k" '+wq' t.txt </dev/null >/dev/null 2>&1) || true
    if ! cmp -s "$d/t.txt" /dev/stdin <<EOF
One two. Three four.

void f(void)
{
    if (x)
    {
        y;
    }
}
#if A
#endif
EOF
    then
        echo "  nopara       $k changed the file:"; sed -n 1,3p "$d/t.txt" | sed 's/^/               /'; exit 1
    fi
done
sample
(cd "$d" && HOME="$d" ./vim -e -s '+5' '+normal! ix' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
grep -q '^    xif (x)$' "$d/t.txt" || { echo "  nopara       the control insert failed"; exit 1; }

# and what stays: [{ still walks out to the enclosing {, % still matches, i{ still selects
sample
(cd "$d" && HOME="$d" ./vim -e -s '+7' '+normal! [{' '+s/^/X/' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
grep -q '^X    {$' "$d/t.txt" || { echo "  nopara       [{ no longer walks out: $(grep -n X "$d/t.txt" | head -1)"; exit 1; }
sample
(cd "$d" && HOME="$d" ./vim -e -s '+4' '+normal! %' '+s/^/X/' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
grep -q '^X}$' "$d/t.txt" || { echo "  nopara       % no longer matches: $(grep -n X "$d/t.txt" | head -1)"; exit 1; }
sample
(cd "$d" && HOME="$d" ./vim -e -s '+7' '+normal! di{' '+wq' t.txt </dev/null >/dev/null 2>&1) || true
# grep -qv is true when ANY line lacks the pattern, so it can pass vacuously: the
# check is that the block's contents are gone and its braces are not.
grep -q '^    {$' "$d/t.txt" || { echo "  nopara       i{ took the enclosing braces too"; exit 1; }
grep -q 'y;' "$d/t.txt" && { echo "  nopara       i{ no longer selects a block -- y; survived"; exit 1; }
# the Ex addresses are refused, so the paragraph is still there afterwards
sample
(cd "$d" && HOME="$d" ./vim -e -s "+'{,'}d" '+wq' t.txt </dev/null >/dev/null 2>&1) || true
grep -q '^One two\. Three four\.$' "$d/t.txt" || { echo "  nopara       '{,'} still addressed a paragraph"; exit 1; }
echo "  nopara       the cut keys do nothing; [{ and % still move; i{ still selects; '{ is refused"

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
