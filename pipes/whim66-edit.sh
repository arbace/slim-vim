#!/bin/sh
# Whim phase 66 -- no sentences, paragraphs, sections, methods, #if blocks or
# comment blocks.  See WHIM-GOAL.md.
#
# Usage: pipes/whim66-edit.sh <work-dir> <state-dir>      (run from the repository root)
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

work=${1:?usage: whim66-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

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

# tools/phaserun.sh sweeps next, then runs pipes/whim66-check.sh.
