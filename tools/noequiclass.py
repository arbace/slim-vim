r"""`[[=a=]]` stops meaning "a with any accent".

Usage:
    python3 tools/noequiclass.py <file>

A POSIX bracket expression has three bracketed forms inside it, and they are
three different features that happen to share a syntax:

    [[:alpha:]]    a character CLASS      -- stays
    [[.x.]]        a collating ELEMENT    -- stays
    [[=a=]]        an equivalence CLASS   -- goes

The third means "this character and every accented form of it", and expanding it
takes **`reg_equi_class()`, 1,397 lines** -- a switch over every base letter
listing its variants across Latin-1, Latin Extended-A and Latin Extended-B.  It
is the largest single function left in the file and the least used: it is
reached only when a pattern contains `[=`, and nothing in the editor writes one.

Two call sites, and removing them is the whole cut:

  * the bracket parser in `regatom()`: the `get_equi_class()` arm goes, so `[=`
    falls through to the collating-element test and then to being taken one
    character at a time.  `[[=a=]]` therefore matches the literal characters
    `[`, `=`, `a` and `]`, which is what a POSIX-unaware regexp engine does.
  * `skip_regexp()`'s scan, which asked the same question only to know how far
    to skip.

`get_equi_class()` and `reg_equi_class()` are then unreachable and the sweep
takes both.  `get_char_class()` and `get_coll_element()` are untouched --
`[[:alpha:]]` and `[[.x.]]` go on working, and so do `\w`, `\a` and the rest,
which are a different mechanism entirely.
"""

import re
import sys
from pathlib import Path


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    # --- the bracket parser -------------------------------------------------
    old = '''                                c_class = get_equi_class(&regparse);
                                if (c_class != 0)
                                {
                                    reg_equi_class(c_class);
                                }
                                else if ((c_class = get_coll_element(&regparse)) != 0)
'''
    new = '''                                if ((c_class = get_coll_element(&regparse)) != 0)
'''
    if old not in text:
        sys.exit('noequiclass: the bracket parser is not where this expects')
    text = text.replace(old, new, 1)
    print('  noequiclass  [= in a bracket expression is no longer an '
          'equivalence class')

    # --- and the scan that only wanted to know how far to skip --------------
    text, n = re.subn(
        r'get_char_class\(&p\) == CLASS_NONE && get_equi_class\(&p\) == 0 && ',
        'get_char_class(&p) == CLASS_NONE && ', text, count=1)
    if n != 1:
        sys.exit("noequiclass: skip_regexp's scan is not where this expects")
    print('  noequiclass  skip_regexp stops asking the same question')

    path.write_text(text, errors='surrogateescape')
    print('  noequiclass  %d mentions left for the sweep'
          % len(re.findall(r'\b(?:reg_equi_class|get_equi_class)\b', text)))


if __name__ == '__main__':
    main()
