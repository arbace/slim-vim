#!/usr/bin/env python3
"""Cut the three ways this editor introduces itself.

Usage:
    python3 tools/nointro.py <file>

An embedded editor starts in a buffer, not on a title card.  Three entry
points, and as everywhere in WHIM-GOAL.md the machinery behind them is found by
the sweep rather than listed here:

  * `:intro` and `:version` point at ex_ni.
  * The splash screen's two call sites go.  `maybe_intro_message()` is called
    from the redraw path when the buffer is empty and no file was named -- it
    is not a command, so pointing a row at ex_ni would leave it showing.

The third door, `--version` and `--help` and `-h`/`-?`, is the command line's,
and tools/dropopts.py removes those with every other option Phase 3 drops.  This
used to turn their branches into `mainerr` calls and leave the comparisons
standing for a later phase to delete, which was two edits and one oversight.
With them go `list_version()` and `usage()`, and with `list_version()` goes
pathdef's `compiled_user` and `compiled_sys`: the BUILDING MACHINE'S HOSTNAME.
"""

import re
import sys
from pathlib import Path

ROWS = ('intro', 'version')


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    n_cmd = 0
    for name in ROWS:
        pat = re.compile(r'(\[CMD_%s\] = \{\(char_u \*\)"%s", sizeof\("%s"\) - 1, )'
                         r'(\w+)' % (name, name, name))
        text, k = pat.subn(lambda m: m.group(1) + 'ex_ni', text)
        if k != 1:
            sys.exit('nointro: expected one row for :%s, matched %d' % (name, k))
        n_cmd += k

    # The splash is a redraw-path call, not a command.  Both sites go; the
    # function itself becomes unreachable and the sweep takes it.
    pat = re.compile(r'^[ \t]*maybe_intro_message\(\);\n', re.M)
    text, n_splash = pat.subn('', text)
    if n_splash != 2:
        sys.exit('nointro: expected two splash call sites, removed %d -- the '
                 'redraw path has moved under this phase' % n_splash)

    path.write_text(text, errors='surrogateescape')
    print('  nointro      :intro and :version to ex_ni, %d splash call sites cut'
          % n_splash)


if __name__ == '__main__':
    main()
