r"""`:command` — user-defined commands.

Usage:
    python3 tools/noucmd.py <file>

`:command` lets a user give a name to an Ex command line and have it dispatched
like a built-in.  The machinery is **1,451 lines**: a parser for the `-nargs`,
`-range`, `-complete` and `-bang` attributes; a per-buffer and a global growable
array of definitions; `uc_check_code()`, 286 lines, expanding `<args>`,
`<q-args>`, `<line1>`, `<count>`, `<bang>`, `<reg>` and `<mods>` into the
replacement text; and a listing mode.

**Without `+eval` a user command can only invoke built-in commands**, which
makes it a way of writing an alias. That is worth 1,451 lines to somebody with a
vimrc, and this editor reads no vimrc — Phase 18 saw to that — so the only way
to define one is to type `:command` by hand in the session where it is used.

Three commands are retired and one dispatch goes:

  * `:command`, `:comclear` and `:delcommand` -> `ex_ni`.
  * `do_ucmd()`, which `do_one_cmd()` reaches when `ea.cmdidx` is negative --
    the marker for "this name is not in cmdnames[], try the user table".  With
    the table gone the name is simply not a command, which is what an unknown
    name should be.
  * `uc_clear(&buf->b_ucmds)` when a buffer is freed, and the `b_ucmds` field
    with it.

THE DELTA IS REAL AND IS DECLARED: `:command` with no arguments lists the
commands defined, which succeeds today, so it moves in the Ex sweep.  So do
`:comclear` and `:delcommand`.  That is three names, and the phase says so in
advance.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def cut(text, pattern, what, count=1, flags=re.M):
    text, n = re.subn(pattern, '', text, count=count, flags=flags)
    if n != count:
        sys.exit('noucmd: %s -- expected %d, matched %d' % (what, count, n))
    return text


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    # --- the dispatch -------------------------------------------------------
    old = '''    if ( ((int)(ea.cmdidx) < 0) )
    {
        do_ucmd(&ea);
    }
    else
    {
'''
    if old not in text:
        sys.exit('noucmd: the user-command dispatch is not where this expects')
    # keep the else body: an unknown name has already been rejected upstream
    blanked = cutil.blank(text)
    k = text.index(old)
    o = blanked.index('{', text.index('else', k + len(old) - 30))
    c = cutil.match(text, o, blanked)
    body = text[text.index('\n', o) + 1:text.rfind('\n', 0, c) + 1]
    body = ''.join(l[4:] if l.startswith('    ') else l
                   for l in body.splitlines(keepends=True))
    end = text.index('\n', c) + 1
    text = text[:k] + body + text[end:]
    print('  noucmd       the dispatch for a name that is not in cmdnames[]')

    # --- the completion that lists them ------------------------------------
    # Six rows of the completion table keep six get_user_cmd_* functions alive,
    # and `expand_user_command_name()` is how `:`-completion walks past the end
    # of cmdnames[] into the user table.  None of them was found by grepping for
    # `do_ucmd` -- a table row is a reference the same as a call.
    text, n = re.subn(
        r'^[ \t]*\{EXPAND_USER_(?:COMMANDS|ADDR_TYPE|CMD_FLAGS|NARGS|COMPLETE|COMPLETEOPT), '
        r'get_user_(?:commands|cmd[a-z_]*), FALSE, TRUE\},\n', '', text, flags=re.M)
    if n != 6:
        sys.exit('noucmd: expected 6 completion rows, matched %d' % n)
    text = text.replace('    return get_user_commands(NULL, idx - (int)CMD_SIZE);',
                        '    return NULL;', 1)

    # find_ucmd() looks a name up in the user table; two callers, one in the
    # completion path and one in do_one_cmd's name scan.
    text, n = re.subn(r'^[ \t]*p = find_ucmd\(eap, p, NULL, xp, complp\);\n', '',
                      text, count=1, flags=re.M)
    text, n2 = re.subn(r'^[ \t]*p = find_ucmd\(eap, p, full, NULL, NULL\);\n', '',
                       text, count=1, flags=re.M)
    if n + n2 != 2:
        sys.exit('noucmd: find_ucmd has %d callers here, expected 2' % (n + n2))

    # and the two `:`-completion contexts that named the user table
    text, n = re.subn(
        r'^[ \t]*case CMD_command:\n[ \t]*return set_context_in_user_cmd\(xp, arg\);\n\n?'
        r'[ \t]*case CMD_delcommand:\n[ \t]*xp->xp_context = EXPAND_USER_COMMANDS;\n'
        r'[ \t]*xp->xp_pattern = arg;\n[ \t]*break;\n\n?', '', text, count=1, flags=re.M)
    if n != 1:
        sys.exit("noucmd: the :command completion contexts are not where this expects")
    print('  noucmd       six completion rows, the name walk past cmdnames[], '
          'and two completion contexts')

    # --- the per-buffer table ----------------------------------------------
    text = cut(text, r'^[ \t]*uc_clear\(&buf->b_ucmds\);\n', "the buffer's table")
    text = cut(text, r'^[ \t]*garray_T    b_ucmds;\n', 'the b_ucmds field')
    print('  noucmd       the per-buffer command table')

    path.write_text(text, errors='surrogateescape')
    print('  noucmd       %d do_ucmd/ucmds mentions left for the sweep'
          % len(re.findall(r'\b(?:do_ucmd|ucmds)\b', text)))


if __name__ == '__main__':
    main()
