#!/usr/bin/env python3
"""The two warnings in Phase 8 that are findings rather than dead code.

Usage:
    python3 tools/findings8.py <vim.c>

The dead-code sweep is not a delete-everything-gcc-names loop, and these are
why.  Both were predicted by GOAL.md and both were there.

`:winpos` parses two numbers that nothing reads any more.  The variables go --
but `getdigits()` advances the pointer it is given, so the CALLS have to stay:
delete them and the second number is parsed out of the first one's text.  That
is the difference between an unused variable and an unused expression, and no
warning distinguishes them.

The swap-file age check compared `st.st_mtime` against `time(NULL) -
sinfo.uptime`, and `uptime` is unsigned, so the whole subtraction is unsigned
and wraps for any file older than the machine's uptime.  The fix is a cast; a
sweep that deleted something here would have been wrong twice over.

Both edits are exact-text replacements and the script fails if either does not
apply -- an upstream that moved these lines needs a human, not a guess.
"""

import sys
from pathlib import Path

EDITS = [
    ('    int x;\n    int y;\n    char_u      *arg = eap->arg;',
     '    char_u      *arg = eap->arg;',
     ':winpos declarations'),
    ('        x = getdigits(&arg);',
     '        (void)getdigits(&arg);',
     ':winpos first call'),
    ('        y = getdigits(&arg);',
     '        (void)getdigits(&arg);',
     ':winpos second call'),
    ('time(NULL) - (sinfo.uptime)',
     'time(NULL) - (time_t)(sinfo.uptime)',
     'swap-file uptime cast'),
]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    for old, new, what in EDITS:
        if old not in text:
            sys.exit('findings8: %s did not apply -- upstream has moved this '
                     'code, and what to do about it is a judgement, not a '
                     'substitution' % what)
        text = text.replace(old, new, 1)

    path.write_text(text, errors='surrogateescape')
    print('  findings     :winpos variables gone and its calls kept; '
          'uptime cast to time_t')


if __name__ == '__main__':
    main()
