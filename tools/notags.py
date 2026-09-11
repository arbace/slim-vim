#!/usr/bin/env python3
"""Remove the tag stack, and everything that walks a tree to find a tags file.

Usage:
    python3 tools/notags.py <file>

A tag jump is the editor discovering, on its own, that a file it was never told
about exists: `get_tagfname()` walks `'tags'` upward from the current file
looking for one, opens whatever it finds, and binary-searches it.  That is
filesystem-layout knowledge of the same kind as `'path'` searching, and it is
the largest single item left -- 2,364 lines reachable only through it.

Retiring the command rows is most of it, but four entry points are NOT commands
and each keeps the whole subtree alive on its own:

  * `nv_help()` -- the <Help> key -- calls `ex_help()`, which calls `do_tag()`.
    `:help` has been `ex_ni` since Phase 1, but the *key* was never cut, so the
    entire help-tag search survived a phase that thought it had removed it.
    This is the clearest case in the tree for cutting entry points rather than
    commands.
  * `nv_tagpop()` -- CTRL-T -- calls `do_tag()` directly from `nv_cmds[]`.
  * `ExpandFromContext()` dispatches EXPAND_TAGS to `expand_tags()`, and
    EXPAND_HELP to `find_help_tags()`.  Completion is a caller like any other.
  * `get_next_completion_match()` dispatches CTRL-X CTRL-] to
    `get_next_tag_completion()`.

CTRL-] is not in that list and does not need to be: `nv_ident()` builds the
string ":ta " and runs it as an Ex command, so retiring the row is enough --
CTRL-] reports that :tag is not available, which is the honest answer.

What this does NOT remove is `vim_findfile()`.  `'tags'` searching and `'path'`
searching share it, and `find_file_in_path_option()` still serves `:find` and
`gf`.  Cutting that is a separate decision, because `gf` is a normal-mode
command a user would miss.
"""

import re
import sys
from pathlib import Path

EDITS = [
    ('the <Help> key, which reached do_tag through ex_help',
     r'[ \t]*if \(!checkclearopq\(cap->oap\)\)\n[ \t]*\{\n'
     r'[ \t]*ex_help\(NULL\);\n[ \t]*\}\n',
     '    (void)checkclearopq(cap->oap);\n', 1),
    ('CTRL-T, the tag stack pop',
     r'[ \t]*if \(!checkclearopq\(cap->oap\)\)\n[ \t]*\{\n'
     r'[ \t]*do_tag\(\(char_u \*\)"", DT_POP[^\n]*\n[ \t]*\}\n',
     '    (void)checkclearopq(cap->oap);\n', 1),
    ('tag completion on the command line',
     r'[ \t]*if \(xp->xp_context == EXPAND_TAGS \|\| xp->xp_context == EXPAND_TAGS_LISTFILES\)\n'
     r'[ \t]*\{\n[ \t]*return expand_tags\([^\n]*\n[ \t]*\}\n', '', 1),
    ('help-tag completion on the command line',
     r'[ \t]*if \(xp->xp_context == EXPAND_HELP\)\n[ \t]*\{\n'
     r'[ \t]*if \(find_help_tags\([^\n]*\n[ \t]*\{\n[ \t]*return OK;\n[ \t]*\}\n'
     r'[ \t]*return FAIL;\n[ \t]*\}\n\n?', '', 1),
    ('the ten command cases that asked for a tag context',
     r'(?:[ \t]*case CMD_(?:tag|stag|ptag|ltag|tselect|stselect|ptselect|tjump|stjump|ptjump):\n)+'
     r'[ \t]*if \(vim_strchr\(p_wop, WOP_TAGFILE\) != NULL\)\n'
     r'[ \t]*\{\n[^\n]*\n[ \t]*\}\n[ \t]*else\n[ \t]*\{\n[^\n]*\n[ \t]*\}\n'
     r'[ \t]*xp->xp_pattern = arg;\n[ \t]*break;\n', '', 1),
    ('CTRL-X CTRL-] tag completion in insert mode',
     r'[ \t]*case  \(5 \+ CTRL_X_WANT_IDENT\) :\n'
     r'[ \t]*get_next_tag_completion\(\);\n[ \t]*break;\n\n?', '', 1),
    ('-complete=tag as a name :command accepts',
     r'[ \t]*\{\(EXPAND_TAGS\), \{\(\(char_u \*\)"tag"\),[^\n]*\n', '', 1),
]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    for what, pat, repl, want in EDITS:
        text, n = re.subn(pat, repl, text, flags=re.M)
        if n != want:
            sys.exit('notags: %s -- expected %d, matched %d' % (what, want, n))
        print('  notags       %s' % what)

    path.write_text(text, errors='surrogateescape')
    print('  notags       %d do_tag mentions and %d find_tags mentions left '
          'for the sweep' % (text.count('do_tag'), text.count('find_tags')))


if __name__ == '__main__':
    main()
