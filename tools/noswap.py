#!/usr/bin/env python3
"""The buffer lives in memory.  Nothing is written that was not asked for.

Usage:
    python3 tools/noswap.py <file>

A swap file is not a recovery add-on bolted to the side of the editor; it is
**memline's backing store**, created beside every file you open, written to as
you type, and deleted on a clean exit.  For an embedded editor that is the last
thing writing a file nobody asked for, and it is the reason `flock`, a
`.swp` name search across `'directory'`, and a 576-line recovery reader exist.

What goes is the *file*, not the memline.  `mf_open()` already supports a
memfile with no name -- that is what `:set noswapfile` has always produced --
so the buffer keeps its block structure and simply never acquires a fd.  The
cost is real and is the point of asking first: **no crash recovery**, and a
buffer larger than memory can no longer page out to disk.

Five entry points, because `ml_open_file()` has seven callers and no-oping the
callers one at a time would be seven chances to miss one:

  * `ml_open_file()` returns having set `b_may_swap = FALSE`, so the callers
    that retry stop retrying.  `findswapname()` -- 262 lines of searching
    `'directory'` for a free `.swp` name -- goes with it.
  * `ml_preserve()`, `ml_sync_all()` and `ml_setname()` become no-ops: flushing,
    syncing and renaming a file that does not exist.
  * the `SEA_RECOVER` arm of the ATTENTION prompt, which is the only path into
    `ml_recover()` once `:recover` is retired.

THE DELTA: `:recover`, `:preserve` and `:swapname` report that they are not
available; so do `:mkvimrc`, `:mkexrc`, `:mksession` and `:mkview`, which wrote
a script into the current directory, and `:checktime`.  `'directory'`,
`'updatecount'` and `'swapsync'` stop existing.  `'swapfile'` cannot go -- it is
PV_BUF, and its row is what initialises the global -- so it stays and is now
always effectively off.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil

STUBS = [
    # The flag matters: check_need_swap() and changed() call this on every
    # edit, and a body that simply returns would search 'directory' again on
    # the next keystroke if the flag were left set.
    ('ml_open_file',  '    buf->b_may_swap = FALSE;'),
    ('ml_preserve',   ''),
    ('ml_sync_all',   ''),
    ('ml_setname',    ''),
]

RECOVER_ARM = (
    r'[ \t]*else if \(swap_exists_action == SEA_RECOVER\)\n'
    r'[ \t]*\{\n(?:[^\n]*\n)*?[ \t]*ml_recover\(FALSE\);\n(?:[^\n]*\n)*?[ \t]*\}\n')


def replace_body(text, name, body):
    blanked = cutil.blank(text)
    m = re.search(r'^%s\([^\n]*\n' % re.escape(name), text, re.M)
    if not m:
        sys.exit('noswap: %s is not defined at file scope any more' % name)
    opening = blanked.index('{', m.end())
    close = cutil.match(text, opening, blanked)
    if close < 0:
        sys.exit('noswap: %s is unbalanced' % name)
    was = text.count('\n', opening, close)
    return text[:opening] + '{\n' + (body + '\n' if body else '') + '}' + text[close + 1:], was


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')

    total = 0
    for name, body in STUBS:
        text, was = replace_body(text, name, body)
        total += was
        print('  noswap       %-14s was %3d lines, is now %s'
              % (name, was, 'one' if body else 'empty'))

    text, n = re.subn(RECOVER_ARM, '', text, flags=re.M)
    if n != 1:
        sys.exit('noswap: expected one SEA_RECOVER arm, matched %d -- it is the '
                 'only way into ml_recover once :recover is retired, and '
                 'leaving it keeps 576 lines alive' % n)
    print('  noswap       the SEA_RECOVER arm of the ATTENTION prompt')

    path.write_text(text, errors='surrogateescape')
    print('  noswap       %d lines stubbed; %d findswapname mentions left for '
          'the sweep' % (total, text.count('findswapname')))


if __name__ == '__main__':
    main()
