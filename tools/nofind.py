#!/usr/bin/env python3
"""A file name means the file of that name, not a file to go looking for.

Usage:
    python3 tools/nofind.py <file>

`'path'` searching is the last of the three ways this editor knew where files
live, after globbing (Phase 11) and `'tags'` (Phase 14).  `vim_findfile()`
walks a path list downward and upward, remembers directories it has visited so
a symlink loop cannot trap it, and can be asked for the second match and the
third -- 866 lines of filesystem-layout knowledge behind `:find`, `:sfind`,
`:tabfind` and `gf`.

`:find`, `:sfind` and `:tabfind` are retired: the whole of what they do is the
search.

**`gf` is kept, and resolves the name literally.** It is the one place a user
names a file from inside the buffer rather than on a command line, and taking
it away would be taking away the naming rather than the searching.  So
`find_file_in_path()` stops consulting `'path'` and answers the only question
left: is there a file of this name?  Fifteen lines against eight hundred and
sixty-six, and it reaches the filesystem no differently from `:e`.

Two details of the contract it has to keep, both visible in
`find_file_name_in_path()`:

  * `first == FALSE` asks for the NEXT match, which is what `3gf` and `]f` use.
    There is never a next one now, so it answers NULL and the caller's loop
    ends -- which is the same answer the search gave when the path held one
    match.
  * the result is owned by the caller, so it is allocated even though the name
    is already in hand.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

BODY = '''    char_u      *name;

    if (!first)
    {
        return NULL;
    }

    name = vim_strnsave(ptr, len);
    if (name == NULL)
    {
        return NULL;
    }

    if (mch_getperm(name) < 0)
    {
        vim_free(name);
        return NULL;
    }

    return name;'''


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')
    blanked = cutil.blank(text)

    m = re.search(r'^find_file_in_path\([^\n]*\n', text, re.M)
    if not m:
        sys.exit('nofind: find_file_in_path is not defined at file scope any more')
    opening = blanked.index('{', m.end())
    close = cutil.match(text, opening, blanked)
    if close < 0:
        sys.exit('nofind: find_file_in_path is unbalanced')
    if 'find_file_in_path_option' not in text[opening:close]:
        sys.exit("nofind: find_file_in_path no longer delegates to the "
                 "'path' search, so this has run already")
    text = text[:opening] + '{\n' + BODY + '\n}' + text[close + 1:]

    path.write_text(text, errors='surrogateescape')
    print('  nofind       find_file_in_path answers "is there a file of this '
          'name?" and nothing else')
    print('  nofind       %d find_file_in_path_option mentions left for the sweep'
          % text.count('find_file_in_path_option'))


if __name__ == '__main__':
    main()
