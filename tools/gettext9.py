#!/usr/bin/env python3
"""Turn _() and NGETTEXT() into functions instead of expanding them.

Usage:
    python3 tools/gettext9.py <file>

These two are the exception to "expand what cannot become an enumerator".
Expanding `_(x)` to `((char_u *)(x))` at 400 call sites works, produces a
smaller file, and silently costs the format diagnostics: glibc declares gettext
with `format_arg(1)`, which tells gcc the return value carries the argument's
format string, so -Wformat, -Wformat-security and -Wformat-nonliteral still see
through the call.  Expand it away and every `emsg(_("E123: %s"), x)` becomes
unchecked.

The check that catches this is therefore not "does it build" but "is the
warning set unchanged", which is why the conversion is here rather than left to
the expander.

The replacement text is fixed and carries an attribute that nothing in the tree
implies, so it is data.  What is computed is where it goes: immediately after
the macros.h banner, where the two definitions were.
"""

import re
import sys
from pathlib import Path

REPLACEMENT = '''// _() and NGETTEXT keep their names as functions rather than being expanded.
// format_arg(1) is how glibc declares gettext: it tells gcc the return value is
// the argument's format string, so -Wformat, -Wformat-security and
// -Wformat-nonliteral still see through the call.  Without it this conversion
// silently loses those diagnostics, which is why the check is that the warning
// set is unchanged, not that it builds.
static inline __attribute__((format_arg(1))) char *_(const char *x)
{
    return (char *)x;
}

static inline __attribute__((format_arg(1))) __attribute__((format_arg(2)))
char *NGETTEXT(const char *x, const char *xs, unsigned long n)
{
    return (char *)((n) == 1 ? x : xs);
}
'''

DEF = re.compile(r'^[ \t]*#[ \t]*define[ \t]+(_|NGETTEXT)\(')


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    lines = path.read_text(errors='surrogateescape').split('\n')

    at = [i for i, l in enumerate(lines) if DEF.match(l)]
    if len(at) != 2:
        sys.exit('gettext9: expected two definitions of _ and NGETTEXT, found %d'
                 % len(at))

    out = []
    for i, line in enumerate(lines):
        if i == at[0]:
            out.extend(REPLACEMENT.split('\n'))
            continue
        if i in at:
            continue
        out.append(line)

    path.write_text('\n'.join(out), errors='surrogateescape')
    print('  gettext      _ and NGETTEXT are inline functions, format_arg kept')


if __name__ == '__main__':
    main()
