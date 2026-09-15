#!/usr/bin/env python3
"""The argument list is walked by :next and :previous, and by nothing else.

Usage:
    python3 tools/noarglist.py <file>

The list itself stays: `vim a b c` fills it, :next and :previous move through
it, `:next x y` replaces it, :drop sets it, and quitting still counts the files
not yet edited.  tools/retire.py points the other rows at ex_ni; this removes
what a row cannot:

  THE SHARED HANDLERS KEEP THEIR OTHER USERS.  :snext went through ex_next, and
  :argdo through ex_listdo with :bufdo and :windo, so only their terms go.
  do_argfile() skipped setting the ' mark for :argdo; it always sets it now.
  ex_rewind() stays because :drop ends in it.

  COMPLETION for :argdo and :argdelete, and the argument-list expansion that
  only :argdelete asked for, so that the sweep takes get_arglist_name().
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def literal(seg, old, new, what, count=1):
    n = seg.count(old)
    if n != count:
        sys.exit('noarglist: %s -- occurs %d times, expected %d' % (what, n, count))
    print('  noarglist    %s' % what)
    return seg.replace(old, new)


def in_function(text, name, edit):
    span = cutil.find_definition(text, name)
    if not span:
        sys.exit('noarglist: %s is not defined at file scope' % name)
    a, z = span
    return text[:a] + edit(text[a:z]) + text[z:]


def sub_once(seg, pattern, what):
    seg, n = re.subn(pattern, '', seg, flags=re.M)
    if n != 1:
        sys.exit('noarglist: %s -- matched %d times, expected 1' % (what, n))
    print('  noarglist    %s' % what)
    return seg


def fold(seg, pattern, what):
    try:
        seg = cutil.fold_never(seg, pattern, 1, re.M)
    except ValueError as e:
        sys.exit('noarglist: %s -- %s' % (what, e))
    print('  noarglist    %s' % what)
    return seg


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    t = path.read_text(errors='surrogateescape')

    # --- the handlers that stay -----------------------------------------------
    t = in_function(t, 'ex_next', lambda s: literal(
        s, ' || eap->cmdidx == CMD_snext', '', ':next asking whether it was :snext'))
    t = in_function(t, 'do_argfile', lambda s: literal(
        s, '    else if (eap->cmdidx != CMD_argdo)\n', '    else\n', 'do_argfile sparing :argdo the mark'))

    def listdo(seg):
        seg = sub_once(seg, r'^[ \t]*case CMD_argdo:\n[ \t]*i = eap->line1 - 1;\n[ \t]*break;\n',
                       ":argdo's starting index")
        seg = fold(seg, r'^[ \t]*if \(eap->cmdidx == CMD_argdo\)$', ':argdo stepping through the list')
        seg = fold(seg, r'^[ \t]*if \(eap->cmdidx == CMD_argdo && i >= eap->line2\)$', ':argdo stopping at its range')
        return seg
    t = in_function(t, 'ex_listdo', listdo)

    # --- completion -----------------------------------------------------------
    def complete(seg):
        seg = sub_once(seg, r'^[ \t]*case CMD_argdo:\n', 'completion for :argdo')
        seg = sub_once(seg, r'^[ \t]*case CMD_argdelete:\n'
                            r"[ \t]*while \(\(xp->xp_pattern = vim_strchr\(arg, ' '\)\) != NULL\)\n"
                            r'[ \t]*\{\n[ \t]*arg = xp->xp_pattern \+ 1;\n[ \t]*\}\n'
                            r'[ \t]*xp->xp_context = EXPAND_ARGLIST;\n[ \t]*xp->xp_pattern = arg;\n'
                            r'[ \t]*break;\n\n',
                       'completion for :argdelete')
        return seg
    t = in_function(t, 'set_context_by_cmdname', complete)
    t = literal(t, '        {EXPAND_ARGLIST, get_arglist_name, TRUE, FALSE},\n', '',
                'the argument-list expansion')

    left = [m.group(0) for m in re.finditer(r'^(?![ \t]*\[?CMD_)[^\n]*\bCMD_(argdo|snext|argdelete)\b[^\n]*$', t, re.M)]
    if left:
        sys.exit('noarglist: still named outside the table: %s' % '; '.join(l.strip() for l in left))

    path.write_text(t, errors='surrogateescape')
    print('  noarglist    only :next and :previous walk the argument list')


if __name__ == '__main__':
    main()
