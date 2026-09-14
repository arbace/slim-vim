r"""C indenting: `'cindent'` and everything `=` did with it.

Usage:
    python3 tools/nocindent.py <file>

`get_c_indent()` is **1,534 lines** and the largest function left in the file: a
model of C syntax built to answer one question, how far to indent this line.  It
knows about labels, scope declarations, `case` bodies, continuation lines,
comment blocks, function arguments, and `'cinoptions'`, a miniature language for
adjusting all of it.  With `in_cinkeys()` and the `cin_*` helpers it comes to
**3,007 lines** of the editor.

`'autoindent'` stays -- it is on by default here -- and copies the previous
line's indent.  That is the behaviour an embedded editor needs; the rest is a C
compiler's front end used for whitespace.

FIVE OPTIONS GO: `'cindent'`, `'cinkeys'`, `'cinoptions'`, `'cinscopedecls'` and
`'cinwords'`.  All five are `PV_BUF`, so the phase pairs `dropoptions --local`
with `droplocal.py`, which is the ordering Phase 16 records.

`'lisp'` and `'indentexpr'` are NOT touched.  They are different indenters that
happen to sit beside this one, and `get_lisp_indent()` is reached from its own
option.

THE `goto` IS THE AWKWARD PART.  Insert mode tests for a re-indent in two
places, hundreds of lines apart, and the first jumps into the second:

    if (cindent_on() && ctrl_x_mode_none())        ... goto force_cindent;
    ...
    if (can_cindent && cindent_on() && ...)  { force_cindent: ... }

So the two have to go together or not at all -- removing the second alone
orphans the label, and removing the first alone leaves a label nothing reaches.

`cindent_on()` itself is left, returning FALSE.  It has seven callers and five
of them only ask whether to do something else instead; rewriting those would be
a bigger change than the one this phase is making, and an editor that answers
"no, this buffer is not C-indented" is telling the truth.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def cut(text, pattern, what, count=1, flags=re.M):
    text, n = re.subn(pattern, '', text, count=count, flags=flags)
    if n != count:
        sys.exit('nocindent: %s -- expected %d, matched %d' % (what, count, n))
    return text


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    # --- insert mode's two re-indent tests, which share a label -------------
    text = cutil.drop_if(
        text, r'^[ \t]*if \(cindent_on\(\) && ctrl_x_mode_none\(\)\)$', flags=re.M)
    text = cutil.drop_if(
        text,
        r'^[ \t]*if \(can_cindent && cindent_on\(\) && ctrl_x_mode_normal\(\)\)$',
        flags=re.M)
    print('  nocindent    insert mode stops re-indenting, and the goto between '
          'its two tests goes with them')

    # --- open_line's C-indent decision -------------------------------------
    text, n = re.subn(
        r'[ \t]*do_cindent = !p_paste && \(curbuf->b_p_cin\)\n'
        r'[ \t]*&& in_cinkeys\([^\n]*\n[ \t]*&& !\(flags & OPENLINE_FORCE_INDENT\);\n',
        '', text, count=1, flags=re.M)
    if n != 1:
        sys.exit("nocindent: open_line's do_cindent is not where this expects")
    text = cut(text, r'^[ \t]*int         do_cindent;\n', "do_cindent's declaration")
    text = text.replace('if (lead_len == 0 && curbuf->b_p_cin && do_cindent && dir == FORWARD',
                        'if (lead_len == 0 && dir == FORWARD', 1)
    # the arm whose whole body was do_c_expr_indent()
    text = cutil.drop_if(
        text,
        r'^[ \t]*else if \(do_cindent \|\| \(curbuf->b_p_ai && use_indentexpr_for_lisp\(\)\)\)$',
        flags=re.M)
    print('  nocindent    open_line stops asking whether to indent as C')

    # --- the `=` operator ---------------------------------------------------
    old = '''                        if (cindent_on())
                        {
                            indent =
                                 get_c_indent();
                        }
                        else
                        {
                            indent = get_indent();
                        }
'''
    new = '''                        indent = get_indent();
'''
    if old not in text:
        sys.exit("nocindent: the `=` operator's C arm is not where this expects")
    text = text.replace(old, new, 1)
    print('  nocindent    `=` indents by the line above, which is what '
          "'autoindent' does")

    # --- preprocs_left: is a `#` line left hanging? ------------------------
    old = """        (curbuf->b_p_si && !curbuf->b_p_cin) ||
        (curbuf->b_p_cin && in_cinkeys('#', ' ', TRUE) && curbuf->b_ind_hash_comment == 0)
        ;"""
    if old not in text:
        sys.exit('nocindent: preprocs_left is not where this expects')
    text = text.replace(old, '        curbuf->b_p_si;', 1)

    # --- fix_indent: lisp indents as lisp ----------------------------------
    old = """    if (curbuf->b_p_lisp && curbuf->b_p_ai)
    {
        if (use_indentexpr_for_lisp())
        {
            do_c_expr_indent();
        }
        else
        {
            fixthisline(get_lisp_indent);
        }
    }
    else if (cindent_on())
    {
        do_c_expr_indent();
    }"""
    if old not in text:
        sys.exit('nocindent: fix_indent is not where this expects')
    text = text.replace(old, """    if (curbuf->b_p_lisp && curbuf->b_p_ai)
    {
        fixthisline(get_lisp_indent);
    }""", 1)

    # --- insert completion's re-indent on accept ---------------------------
    # want_cindent is (get_can_cindent() && cindent_on()), so it is FALSE.
    text = cut(text, r'^[ \t]*want_cindent = \(get_can_cindent\(\) && cindent_on\(\)\);\n\n?',
               "ins_compl_stop's want_cindent")
    text = cut(text,
               r'[ \t]*if \(want_cindent\)\n[ \t]*\{\n'
               r'[ \t]*do_c_expr_indent\(\);\n[ \t]*want_cindent = FALSE;\n[ \t]*\}\n',
               "its first use")
    text = cut(text,
               r"[ \t]*if \(want_cindent && in_cinkeys\(KEY_COMPLETE, ' ', inindent\(0\)\)\)\n"
               r"[ \t]*\{\n[ \t]*do_c_expr_indent\(\);\n[ \t]*\}\n",
               "its second use")
    text = cut(text, r'^[ \t]*int[ \t]+want_cindent;\n', "its declaration")

    # --- the `=` operator, which is where it is actually spelled -----------
    # op_reindent() takes the indenter as a FUNCTION POINTER, which is why a
    # grep for `get_c_indent(` does not find this one.  Without a C indenter,
    # `=` sets each line's indent to the indent it already has: a no-op, which
    # is the honest answer for a buffer whose language the editor cannot read.
    text = text.replace('                op_reindent(oap, get_c_indent);',
                        '                op_reindent(oap, get_indent);', 1)

    # --- internal_format's line-comment hunt -------------------------------
    text = cutil.drop_if(
        text, r'^[ \t]*if \(leader_len == 0 && curbuf->b_p_cin\)$', flags=re.M)
    print('  nocindent    preprocs_left, fix_indent, completion, `=` and the '
          'comment hunt in internal_format')

    # may_do_si(): 'smartindent' defers to 'cindent' when both are set.  There
    # is no 'cindent' to defer to.
    old = """    return curbuf->b_p_si
        && !curbuf->b_p_cin
        && !p_paste;"""
    if old not in text:
        sys.exit('nocindent: may_do_si is not where this expects')
    text = text.replace(old, """    return curbuf->b_p_si
        && !p_paste;""", 1)
    print("  nocindent    'smartindent' stops deferring to an option that is gone")

    # 'cinwords' told 'smartindent' which keywords begin a block.
    text, n = re.subn(
        r"[ \t]*else if \(last_char != ';' && last_char != '\}' && cin_is_cinword\(ptr\)\)\n"
        r'[ \t]*\{\n[ \t]*did_si = TRUE;\n[ \t]*\}\n', '', text, count=1, flags=re.M)
    if n != 1:
        sys.exit("nocindent: 'smartindent' does not consult cin_is_cinword here")

    # parse_cino() turns 'cinoptions' into the b_ind_* fields.  Two callers,
    # neither of which is about indenting: opening a buffer, and resizing.
    # FOUR callers, not two: 'shiftwidth' re-parses 'cinoptions' because some
    # of them are expressed in shiftwidths, and check_buf_options() re-parses
    # on every option check.  Neither is about indenting; both just keep the
    # b_ind_* fields in step with a string that no longer exists.
    text = cut(text, r'^[ \t]*parse_cino\(curbuf\);\n', 'a parse_cino call', count=3)
    text = cut(text, r'^[ \t]*parse_cino\(buf\);\n', "check_buf_options' parse_cino")
    text, ok = cutil.delete_definition(text, 'parse_cino')
    if not ok:
        sys.exit('nocindent: parse_cino is not defined at file scope')
    print("  nocindent    'cinwords' for 'smartindent', and 'cinoptions' parsing")

    # --- and the wrapper whose whole body was fixthisline(get_c_indent) -----
    text, ok = cutil.delete_definition(text, 'do_c_expr_indent')
    if not ok:
        sys.exit('nocindent: do_c_expr_indent is not defined at file scope')

    # cindent_on() stays and answers no: five of its seven callers only ask in
    # order to do something else instead.
    blanked = cutil.blank(text)
    m = re.search(r'^cindent_on\(void\)\n', text, re.M)
    if not m:
        sys.exit('nocindent: cindent_on is not defined at file scope')
    o = blanked.index('{', m.end())
    c = cutil.match(text, o, blanked)
    text = text[:o] + '{\n    return FALSE;\n}' + text[c + 1:]
    print('  nocindent    cindent_on() answers no, which is now true')

    path.write_text(text, errors='surrogateescape')
    print('  nocindent    %d get_c_indent/in_cinkeys mentions left for the sweep'
          % len(re.findall(r'\b(?:get_c_indent|in_cinkeys)\b', text)))


if __name__ == '__main__':
    main()
