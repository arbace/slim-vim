#!/usr/bin/env python3
r"""Stop expanding wildcards at all.  A pattern names a file, literally.

Usage:
    python3 tools/noglob.py <file>

Phase 10 removed the expander that wrote shell scripts.  What was left was the
editor's own: `gen_expand_wildcards()` walking directories with `opendir` and
`readdir`, matching `*`, `?`, `[...]`, `~` and `$VAR` in process.  That is the
editor knowing what is on the disk around the file it was given, and it is the
boundary this fork is here to narrow.

So the whole function becomes what its own fallback already was -- hand the
patterns back unchanged.  `save_patterns()` is not a stub written for this; it
is the path vim already took for a pattern with no wildcard in it, and it does
the one thing that still has to happen, `backslash_halve()`.

WHAT THIS COSTS, and it is not small: `:e *.c` opens one buffer named `*.c`,
and **file-name completion stops working** -- `:e ali<Tab>` produced `alias.c`
by globbing `ali*`, and now produces `ali\*`.  Both were measured on a build
before this was written down.  A shell expands `*.c` before vim ever sees it,
which is where the argument is that this belongs outside; inside the editor it
is 1,025 lines and two syscalls.

NOT touched here, and worth saying because it looks like it should be:
`opendir` and `readdir` do not go with this.  They are held by the temp
directory -- `vim_opentempdir` and `delete_recursive` via `readdir_core` --
which exists so `:%!sort` has somewhere to put a file, and which dies with
shell-out in the next phase rather than with globbing in this one.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')
    blanked = cutil.blank(text)

    m = re.search(r'^gen_expand_wildcards\([^\n]*\n', text, re.M)
    if not m:
        sys.exit('noglob: gen_expand_wildcards is not defined at file scope any '
                 'more, and replacing a function by guesswork is how an editor '
                 'stops opening files')
    # Brace matching, not a scan: this body holds the literal "*?[{", and a
    # depth count that believes that brace runs off the end of the file.
    opening = blanked.index('{', m.end())
    close = cutil.match(text, opening, blanked)
    if close < 0:
        sys.exit('noglob: gen_expand_wildcards is unbalanced')
    was = text.count('\n', opening, close)

    text = (text[:opening]
            + '{\n    return save_patterns(num_pat, pat, num_file, file);\n}'
            + text[close + 1:])
    path.write_text(text, errors='surrogateescape')
    print('  noglob       gen_expand_wildcards was %d lines, is now one; every '
          'pattern names a file' % was)


if __name__ == '__main__':
    main()
