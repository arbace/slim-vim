#!/bin/sh
# Whim phase 57 -- no lisp.  See WHIM-GOAL.md.
#
# Usage: pipes/whim57-edit.sh <work-dir> <state-dir>      (run from the repository root)
#
# 'lisp' and 'lispwords' go, and with them everything they switched on:
# get_lisp_indent() for autoindent, =, gq and new lines; lisp_match() over
# 'lispwords'; '-' as a keyword character; ';' line comments in check_linecomment();
# and findmatchlimit()'s lisp mode, which stopped % at a ';' comment and skipped
# #\( and #\[ character literals.  'lispoptions' went in Phase 55.
#
# b_p_lisp is folded as FALSE at every reader rather than stubbed, so each branch
# it guarded is either gone or taken unconditionally.
#
# THE DELTA: none the harnesses record -- no case sets 'lisp'.  The probes check
# the two options are unknown and that % still matches across a ';'.
set -eu

work=${1:?usage: whim57-edit.sh <work-dir> <state-dir>}
f="$work/whim-vim.c"

python3 - "$f" <<'PY'
import re, sys
sys.path.insert(0, 'tools')
import cutil
path = sys.argv[1]
t = open(path, errors='surrogateescape').read()

def die(msg):
    sys.exit('  nolisp       ' + msg)

def say(what):
    print('  nolisp       ' + what)

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

def always(s, pattern, what):
    """An if whose condition is now always true: keep its body, and lose an else."""
    once(s, pattern, what)
    m = re.search(pattern, s, re.M)
    b = cutil.blank(s)
    k, o, c, head = cutil._guarded(s, m, b)
    if head != 'if':
        die('%s -- not a plain if' % what)
    end = s.index('\n', c) + 1
    body = cutil._dedent4(s[s.index('\n', o) + 1:s.rfind('\n', 0, c) + 1])
    rest = s[end:]
    nxt = re.match(r'[ \t]*else\b', rest)
    if nxt:
        if re.match(r'[ \t]*else[ \t]+if\b', rest):
            die('%s -- an else if follows' % what)
        o2 = b.index('{', end + nxt.end())
        c2 = cutil.match(s, o2, b)
        end = s.index('\n', c2) + 1
    say(what)
    return s[:k] + body + s[end:]

def literal(s, old, new, what):
    k = s.count(old)
    if k != 1:
        die('%s -- occurs %d times, expected 1' % (what, k))
    say(what)
    return s.replace(old, new)

def sub(s, pattern, new, what):
    s, k = re.subn(pattern, new, s, flags=re.M)
    if k != 1:
        die('%s -- matched %d times, expected 1' % (what, k))
    say(what)
    return s

def openline(s):
    s = drop_if(s, r'^[ \t]*if \(leader == NULL && !use_indentexpr_for_lisp\(\) && curbuf->b_p_lisp && curbuf->b_p_ai\)$',
                'a new line taking its indent from get_lisp_indent()')
    s = sub(s, r'^[ \t]*if \(!p_paste\)\n[ \t]*\{\n[ \t]*\}\n\n?', '', "open_line's now-empty 'paste' test")
    return s
t = in_function(t, 'open_line', openline)
t = in_function(t, 'buf_init_chartab', lambda s: drop_if(s, r'^[ \t]*if \(buf->b_p_lisp\)$', "'-' as a keyword character"))
t = in_function(t, 'check_linecomment', lambda s: fold_never(s, r'^[ \t]*if \(curbuf->b_p_lisp\)$', "a ';' starting a line comment"))
t = in_function(t, 'op_reindent', lambda s: always(
    s, r'^[ \t]*if \(i != oap->line_count - 1 \|\| oap->line_count == 1 \|\| how != get_lisp_indent\)$',
    '= skipping the last line only for lisp'))
t = in_function(t, 'fix_indent', lambda s: drop_if(s, r'^[ \t]*if \(curbuf->b_p_lisp && curbuf->b_p_ai\)$', 'fix_indent re-indenting lisp'))
t = in_function(t, 'do_pending_operator', lambda s: drop_if(s, r'^[ \t]*if \(curbuf->b_p_lisp\)$', '= indenting lisp'))
t = in_function(t, 'format_lines', lambda s: fold_never(s, r'^[ \t]*else if \(curbuf->b_p_lisp\)$', 'gq indenting lisp'))

def match(s):
    s = sub(s, r'^[ \t]*int[ \t]+lispcomm = FALSE;\n', '', '% without a lisp comment state')
    s = sub(s, r'^[ \t]*int[ \t]+lisp = curbuf->b_p_lisp;\n', '', '% without lisp mode')
    s = literal(s, 'if ((backwards && comment_dir) || lisp || skip_comments)', 'if ((backwards && comment_dir) || skip_comments)',
                '% looking for a comment only for a comment direction or FM_SKIPCOMM')
    s = drop_if(s, r'^[ \t]*if \(lisp && comment_col != MAXCOL && pos\.col > \(colnr_T\)comment_col\)$', '% starting inside a lisp comment')
    s = drop_if(s, r'^[ \t]*if \(lispcomm && pos\.col < \(colnr_T\)comment_col\)$', '% stopping at a lisp comment backwards')
    s = literal(s, 'if (comment_dir || lisp || skip_comments)', 'if (comment_dir || skip_comments)', '% rescanning a line for lisp')
    s = fold_never(s, r'^[ \t]*if \(lisp && comment_col != MAXCOL\)$', '% jumping to a lisp comment backwards')
    s = literal(s, 'if (linep[pos.col] == NUL || (lisp && comment_col != MAXCOL && pos.col == (colnr_T)comment_col))',
                'if (linep[pos.col] == NUL)', '% ending a line at a lisp comment')
    s = literal(s, 'if (pos.lnum == curbuf->b_ml.ml_line_count || lispcomm)', 'if (pos.lnum == curbuf->b_ml.ml_line_count)',
                '% stopping at a lisp comment forwards')
    s = literal(s, 'if (lisp || skip_comments)', 'if (skip_comments)', '% scanning the next line for lisp')
    s = drop_if(s, r'^[ \t]*if \(curbuf->b_p_lisp && vim_strchr\(\(char_u \*\)"\{\}\(\)\[\]", c\) != NULL', '% skipping #\\( character literals')
    return s
t = in_function(t, 'findmatchlimit', match)

open(path, 'w', errors='surrogateescape').write(t)
PY

tools/st.sh dropoptions "$f" --local lisp lispwords

tools/sweep.sh "$f"
tools/st.sh droplocal "$f" b_p_lisp b_p_lw

# tools/phaserun.sh sweeps next, then runs pipes/whim57-check.sh.
