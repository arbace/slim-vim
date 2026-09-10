#!/usr/bin/env python3
"""Cut the three ways this editor introduces itself.

Usage:
    python3 tools/nointro.py <file>

An embedded editor starts in a buffer, not on a title card.  Three entry
points, and as everywhere in PURE-GOAL.md the machinery behind them is found by
the sweep rather than listed here:

  * `:intro` and `:version` point at ex_ni.
  * The splash screen's two call sites go.  `maybe_intro_message()` is called
    from the redraw path when the buffer is empty and no file was named -- it
    is not a command, so pointing a row at ex_ni would leave it showing.

  * `--version`, `--help` and `-h`/`-?` stop being options.  Their branches do
    what an unrecognised option already does -- `mainerr(ME_UNKNOWN_OPTION)` --
    so there is no special case left behind and no branch that exists only to
    refuse.  With them go `list_version()` and `usage()`, and with
    `list_version()` goes everything it printed: pathdef's `compiled_user` and
    `compiled_sys` bake the BUILDING MACHINE'S HOSTNAME into the binary, which
    is worth removing on an embedded artifact's account and worth removing
    twice on a reproducible one.
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

    # The command line's three doors to the same two functions.  Each becomes
    # the error an unknown option already produces, so nothing is left that
    # exists only to say no.
    UNKNOWN = 'mainerr(ME_UNKNOWN_OPTION, (char_u *)argv[0]);'
    n_arg = 0
    for old, new in (
        ('                    usage();\n',
         '                    %s\n' % UNKNOWN),
        ('''                    cmdline_width = Columns = 80;
                    info_message = TRUE;
                    list_version();
                    msg_putchar('\\n');
                    msg_didout = FALSE;
                    mch_exit(0);
''',
         '                    %s\n' % UNKNOWN),
        ('                usage();\n                break;\n',
         '                %s\n                break;\n' % UNKNOWN),
    ):
        if old not in text:
            sys.exit('nointro: this command-line branch has moved under the '
                     'phase:\n%s' % old)
        text = text.replace(old, new, 1)
        n_arg += 1

    path.write_text(text, errors='surrogateescape')
    print('  nointro      :intro and :version to ex_ni, %d splash call sites cut, '
          '%d command-line options now unknown' % (n_splash, n_arg))


if __name__ == '__main__':
    main()
