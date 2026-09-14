r"""Insert completion, and the popup menu that shows it.

Usage:
    python3 tools/nocompl.py <file>

CTRL-N and CTRL-P complete the word being typed, and CTRL-X opens a submenu of
sources to complete *from*: the current file, `'dictionary'`, `'thesaurus'`,
tags, file names, spelling, whole lines, the command line, a register, a user
function.  The matches are shown in a popup menu, kept in a growable array,
cycled, filtered as more is typed, and re-indented on accept.

Almost none of those sources still exists.  Tags went in Phase 12, spelling was
never in a `tiny` build, `'completefunc'` needs `+eval`, and file-name
completion goes through the globbing Phase 9 removed.  What is left is the
current file -- and an editor with no vimrc, whose user is typing into it
directly, is not a place where a word list earns 3,831 lines.

**The cut is five stubs and the sweep.**  This subsystem is reached only through
predicates, which is what makes that work: `edit()` has sixteen
`goto docomplete` sites and every one is guarded by `ctrl_x_mode_*()`,
`pum_visible()`, `ins_compl_active()` or `ins_compl_has_autocomplete()`.  Answer
those honestly and every branch is dead:

    ins_complete()                 -> FAIL      the entry point
    ins_compl_prep()               -> FALSE     the per-key hook
    ins_compl_active()             -> FALSE
    pum_visible()                  -> FALSE
    ins_compl_has_autocomplete()   -> FALSE

`funcreach.py` then takes the interior -- the sources, the match array, the pum
drawing and the CTRL-X submode machinery -- because nothing reaches it any more.

NINE OPTIONS GO: `'autocomplete'`, `'complete'`, `'completefunc'`,
`'completeopt'`, `'dictionary'`, `'infercase'`, `'pumheight'`, `'pumwidth'` and
`'thesaurus'`.  Six are buffer-local, so the rows go with `--local` and the
fields with `droplocal.py` after the sweep.

WHAT STAYS: CTRL-N and CTRL-P remain ordinary insert-mode keys that insert
nothing, which is what an unbound key does.  The `docomplete:` label and its
gotos remain too -- they reach a stub that fails, which is the same shape as
`ex_ni` for an Ex command, and unpicking sixteen `goto`s out of a 3,000-line
switch would be a larger and riskier change than the one this phase makes.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

def cut(text, pattern, what, count=1, flags=re.M):
    text, n = re.subn(pattern, '', text, count=count, flags=flags)
    if n != count:
        sys.exit('nocompl: %s -- expected %d, matched %d' % (what, count, n))
    return text


STUBS = (
    ('ins_complete', '    return FAIL;'),
    ('ins_compl_prep', '    return FALSE;'),
    ('ins_compl_active', '    return FALSE;'),
    ('pum_visible', '    return FALSE;'),
    ('ins_compl_has_autocomplete', '    return FALSE;'),
    # and the three hooks the popup menu has into the redraw loop, which are
    # reached from update_screen() rather than from completion -- so answering
    # pum_visible() is not enough to orphan pum_redraw().
    ('pum_redraw_in_same_position', '    return FALSE;'),
    ('pum_may_redraw', ''),
    ('pum_undisplay', ''),
    # and the drawing entry point itself, so the island behind it is orphaned
    # whichever caller survives -- chasing them one at a time found three and
    # missed two.
    ('pum_display', ''),
)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    total = 0
    for name, rep in STUBS:
        blanked = cutil.blank(text)
        m = re.search(r'^%s\(' % re.escape(name), text, re.M)
        if not m:
            sys.exit('nocompl: %s is not defined at file scope' % name)
        o = blanked.index('{', m.end())
        c = cutil.match(text, o, blanked)
        total += text.count('\n', o, c)
        text = text[:o] + '{\n' + (rep + '\n' if rep else '') + '}' + text[c + 1:]
    print('  nocompl      %d lines stubbed in the five predicates the whole '
          'subsystem hangs from' % total)

    # One reader the sweep cannot reach, because it is inside edit(): the guard
    # that sends CTRL-N and CTRL-P to `normalchar` when 'complete' is empty.
    # With the option gone there is nothing to test, and the two keys should
    # take that path unconditionally -- which is what `goto normalchar` already
    # said they should.
    text = cutil.drop_if(
        text,
        r"^[ \t]*if \(\*curbuf->b_p_cpt == NUL && \(ctrl_x_mode_normal\(\) \|\| "
        r"ctrl_x_mode_whole_line\(\)\)", flags=re.M)
    print("  nocompl      edit()'s test for an empty 'complete'")

    # has_compl_option() complains that 'dictionary' or 'thesaurus' is empty.
    # Both options are going, and its two callers are the CTRL-X submode arms
    # for them -- guarded by ctrl_x_mode_thesaurus() and ctrl_x_mode_dictionary(),
    # which can no longer be true.  The arms collapse to what they already did
    # when the option was empty.
    text, n = re.subn(
        r'[ \t]*if \(c == Ctrl_T && ctrl_x_mode_thesaurus\(\)\)\n[ \t]*\{\n'
        r'[ \t]*if \(has_compl_option\(FALSE\)\)\n[ \t]*\{\n'
        r'[ \t]*goto docomplete;\n[ \t]*\}\n[ \t]*break;\n[ \t]*\}\n\n?',
        '', text, count=1, flags=re.M)
    text, n2 = re.subn(
        r'[ \t]*if \(ctrl_x_mode_dictionary\(\)\)\n[ \t]*\{\n'
        r'[ \t]*if \(has_compl_option\(TRUE\)\)\n[ \t]*\{\n'
        r'[ \t]*goto docomplete;\n[ \t]*\}\n[ \t]*break;\n[ \t]*\}\n',
        '', text, count=1, flags=re.M)
    if n + n2 != 2:
        sys.exit("nocompl: the CTRL-X dictionary/thesaurus arms are not where "
                 "this expects (%d, %d)" % (n, n2))
    text, ok = cutil.delete_definition(text, 'has_compl_option')
    if not ok:
        sys.exit('nocompl: has_compl_option is not defined at file scope')

    # 'infercase' asked smartcase to stand down while completing.
    text = text.replace(
        'if (ic && !no_smartcase && scs && !(ctrl_x_mode_not_default() && curbuf->b_p_inf))',
        'if (ic && !no_smartcase && scs)', 1)

    # and `:set autocomplete<`, which is how a buffer-local boolean is reset to
    # "ask the global".
    # `:set autocomplete<` resets a buffer-local boolean to "ask the global".
    # It is the FIRST arm of an else-chain, so removing it has to promote the
    # next one: dropping the arm and leaving `else if` behind produced a
    # dangling `else` and a function that fell off its end -- which gcc caught
    # as "control reaches end of non-void function", 30 lines away.
    text, n = re.subn(
        r'([ \t]*)if \(\(int \*\)varp == &curbuf->b_p_ac && opt_flags == OPT_LOCAL\)\n'
        r'[ \t]*\{\n[ \t]*value = -1;\n[ \t]*\}\n[ \t]*else (if \()',
        r'\1\2', text, count=1, flags=re.M)
    if n != 1:
        sys.exit("nocompl: `:set autocomplete<` is not where this expects")
    text = re.sub(r'^[ \t]*(?:curbuf|buf)->b_p_ac = -1;\n', '', text, flags=re.M)
    # set_shellsize_inner() redraws the popup menu when the terminal resizes --
    # a live path into the pum that completion itself does not reach.
    #
    # SCOPED TO THAT FUNCTION: there are six `if (pum_visible())` in the file
    # and an unanchored cut took the first, which is an arrow-key case in
    # edit().  Harmless there, because the guard is now false either way, but
    # not what was meant -- and the same mistake as `case 't':` and
    # `settmode(TMODE_COOK)` before it.
    import funcreach
    blanked = cutil.blank(text)
    a0, z0 = funcreach.definitions(text, blanked)['set_shellsize_inner']
    fn = text[a0:z0]
    fn2 = cutil.drop_if(fn, r'^[ \t]*if \(pum_visible\(\)\)$', flags=re.M)
    if 'ins_compl_show_pum' in fn2:
        sys.exit("nocompl: set_shellsize_inner's pum block is not the one cut")
    text = text[:a0] + fn2 + text[z0:]
    print("  nocompl      has_compl_option, 'infercase' in smartcase, "
          "`:set autocomplete<`, and the pum's resize hook")

    # didset_string_options() dereferences every string option's global once at
    # startup.  This is the FOURTH phase to meet it -- 20, 29, 30 and now this
    # one -- and here it was a segfault before the first keystroke, because
    # `'completeopt'`'s row goes and nothing else reads p_cot.
    text = cut(text,
               r'^[ \t]*\(void\)opt_strings_flags\(p_cot, p_cot_values, '
               r'&cot_flags, TRUE\);\n',
               "didset_string_options' p_cot line")
    print("  nocompl      didset_string_options stops reading 'completeopt'")

    path.write_text(text, errors='surrogateescape')


if __name__ == '__main__':
    main()
