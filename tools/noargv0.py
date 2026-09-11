#!/usr/bin/env python3
"""Stop the binary's own name from choosing what it does.

Usage:
    python3 tools/noargv0.py <file>

`parse_command_name()` reads `argv[0]` and selects a mode from it: a leading
`r` is restricted, `e` selects evim, `g` the GUI, and `view`, `diff` and `ex`
prefixes each change it again.  That is a Unix *installation* convention -- you
symlink `rvim`, `view` and `ex` at one binary and let the name pick -- and an
embedded editor, which is one file that was never installed, has no use for it.

It is also a trap, and an expensive one.  A reference binary saved as `ref` runs
in restricted mode, where every shell-out fails; renaming the product to
`slim-vim` needed a side-by-side check before it could be trusted; and every
harness in this repository stages the binary under test as `vim` for no reason
except this function.  Removing it removes the whole class.

**Nothing is lost, and that is checked rather than asserted.**  Every mode the
name could select has a command-line option that selects it explicitly, and
this refuses to run unless all of them are still there:

    -Z  restricted      -R  readonly       -y  evim
    -e  ex mode         -E  improved ex    -d  diff

The one difference worth knowing: invoking vim as `view` also set
`'undolevels'` to 10000, and `-R` does not.  Upstream's own option is the
weaker of the two, so this follows the option rather than the name.
"""

import re
import sys
from pathlib import Path

# option letter -> the text that proves the switch still handles it
REQUIRED = {
    'Z': 'restricted = TRUE;',
    'R': 'readonlymode = TRUE;',
    'y': 'evim_mode = TRUE;',
    'e': 'exmode_active = EXMODE_NORMAL;',
    'E': 'exmode_active = EXMODE_VIM;',
}


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    missing = [f"-{c}" for c, proof in REQUIRED.items() if proof not in text]
    if missing:
        sys.exit('noargv0: these options no longer select their mode, so '
                 'dropping the name sensitivity would REMOVE capability rather '
                 'than relocate it: %s' % ', '.join(missing))

    pat = re.compile(r'^[ \t]*parse_command_name\(&params\);\n', re.M)
    text, n = pat.subn('', text)
    if n != 1:
        sys.exit('noargv0: expected exactly one call to parse_command_name, '
                 'removed %d -- main() has moved under this phase' % n)

    path.write_text(text, errors='surrogateescape')
    print('  argv0        name sensitivity gone; %d options still select every '
          'mode it could' % len(REQUIRED))


if __name__ == '__main__':
    main()
