#!/usr/bin/env python3
"""The editor stops re-reading a file it has already read.

Usage:
    python3 tools/nostat.py <file>

vim watches the files it holds.  `check_timestamps()` walks every buffer and
stats its file -- from the main loop, from insert mode, from the
`Press ENTER` prompt, and whenever the terminal regains focus -- and
`buf_check_timestamp()` does the same for one buffer on entering it.  If the
file has moved underneath, it prompts, and with `'autoread'` it reloads.

That is the editor initiating filesystem traffic on its own account, which is
the boundary this fork narrows.  Phase 15 retired `:checktime`, which removed
the *command*; this removes the *polling*, which is what actually reached the
disk.  What is left is an editor that reads a file when told to and writes it
when told to.

The two entry points, and the five calls between them:

  * `check_timestamps()` returns 0 without looking at anything.  Its four
    callers -- main_loop(), edit(), wait_return() and ui_focus_change() -- are
    the poll, and they keep calling a function that now says "nothing changed".
    Stubbing rather than unpicking them is deliberate: each sits in a different
    control structure and each already handles that answer.
  * the three direct `buf_check_timestamp()` calls, in do_ecmd(), enter_buffer()
    and ex_drop(), are deleted, because with the poll gone they are the only
    thing keeping 339 lines of checking and reloading alive.

NOT touched: `check_mtime()`, which `buf_write()` calls before overwriting a
file that has changed since it was read.  That is not polling -- it happens only
when the user asks to write, and it is what stops a write from silently
clobbering someone else's edit.  `b_mtime_read` is still recorded on read, so it
still works.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

CALLS = [
    (r'^[ \t]*\(void\)buf_check_timestamp\(curbuf, FALSE\);\n', 'do_ecmd'),
    (r'^[ \t]*\(void\)buf_check_timestamp\(buf, FALSE\);\n', 'enter_buffer'),
    (r'^[ \t]*buf_check_timestamp\(curbuf, FALSE\);\n', 'ex_drop'),
]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    blanked = cutil.blank(text)
    m = re.search(r'^check_timestamps\([^\n]*\n', text, re.M)
    if not m:
        sys.exit('nostat: check_timestamps is not defined at file scope any more')
    opening = blanked.index('{', m.end())
    close = cutil.match(text, opening, blanked)
    if close < 0:
        sys.exit('nostat: check_timestamps is unbalanced')
    was = text.count('\n', opening, close)
    text = text[:opening] + '{\n    return 0;\n}' + text[close + 1:]
    print('  nostat       check_timestamps was %d lines, and now looks at nothing'
          % was)

    for pat, where in CALLS:
        text, n = re.subn(pat, '', text, flags=re.M)
        if n != 1:
            sys.exit('nostat: expected one buf_check_timestamp call in %s, '
                     'matched %d' % (where, n))
        print('  nostat       %s stops checking on the way in' % where)

    path.write_text(text, errors='surrogateescape')
    print('  nostat       %d buf_check_timestamp mentions left for the sweep'
          % text.count('buf_check_timestamp'))


if __name__ == '__main__':
    main()
