#!/usr/bin/env python3
"""The arrow keys still move the cursor, in insert mode and in normal mode.

Usage:
    python3 tools/arrowcheck.py <binary>

Up, Down, PageUp and PageDown each began with

    if (pum_visible())
    {
        goto docomplete;
    }

which is how they moved the selection in a completion menu instead of the
cursor.  The phase that removes the menu removes those four arms, and the risk
it takes is the obvious one: cutting the guard and the key's real body together
would leave insert mode with no vertical motion at all, which no completion
check would notice.

**IT HAS TO BE A PTY.**  An arrow key arrives as an escape sequence and is
decoded from the terminal key table; under `-e -s` the table is never built.

From `one/two/three`, `A` at the end of line 1 leaves the cursor past `one`;
Down must put it past `two`, so typing `X` gives `twoX`.  Pressing the same keys
with the arm miscut leaves the `X` on line 1.
"""

import os
import pty
import shutil
import sys
import tempfile
import time


def run(binary, keys):
    d = tempfile.mkdtemp()
    try:
        shutil.copy(binary, os.path.join(d, 'vim'))
        with open(os.path.join(d, 'f.txt'), 'w') as fh:
            fh.write('one\ntwo\nthree\n')
        pid, fd = pty.fork()
        if pid == 0:
            os.environ['TERM'] = 'xterm'
            # No -u NONE: an empty $HOME, $VIM and $VIMRUNTIME are the isolation.
            os.environ.update(HOME=d, VIM=os.path.join(d, 'novim'),
                              VIMRUNTIME=os.path.join(d, 'novim'), XDG_CONFIG_HOME=os.path.join(d, 'xdg'))
            for k in ('VIMINIT', 'EXINIT', 'MYVIMRC'):
                os.environ.pop(k, None)
            os.chdir(d)
            os.execv('./vim', ['vim', 'f.txt'])
            os._exit(127)
        time.sleep(0.9)
        for k in keys:
            os.write(fd, k)
            time.sleep(0.35)
        time.sleep(0.9)
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
        os.close(fd)
        return open(os.path.join(d, 'f.txt')).read().replace('\n', ' ')
    finally:
        shutil.rmtree(d, ignore_errors=True)


DOWN = b'\x1b[B'
UP = b'\x1b[A'


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    b = os.path.abspath(sys.argv[1])

    got = run(b, (b'gg', b'A', DOWN, b'X', b'\x1b', b':wq\r'))
    if got != 'one twoX three ':
        print('  arrowcheck   Down in insert mode gave %r, expected %r'
              % (got, 'one twoX three '))
        return 1

    got = run(b, (b'G', b'A', UP, b'X', b'\x1b', b':wq\r'))
    if got != 'one twoX three ':
        print('  arrowcheck   Up in insert mode gave %r, expected %r'
              % (got, 'one twoX three '))
        return 1

    # NORMAL MODE TOO, and in the form a terminal actually sends.  vim switches
    # the keypad to application mode at startup, so an xterm sends `ESC O B`,
    # not `ESC [ B`.  Normal mode finds a key through nv_cmd_idx[], a sorted
    # index into nv_cmds[] computed once and written into the C -- delete a row
    # and every key past it resolves to the wrong one.  Phase 24 did exactly
    # that, and for twelve phases nothing noticed, because insert mode decodes
    # the arrows in a switch and this check only asked insert mode.
    for name, key, keys, want in (
            ('Down', b'\x1bOB', (b'gg0',), 'one wo three '),
            ('Up', b'\x1bOA', (b'G0',), 'one wo three '),
            ('Right', b'\x1bOC', (b'gg0',), 'oe two three '),
            ('Left', b'\x1bOD', (b'gg$',), 'oe two three ')):
        got = run(b, keys + (key, b'x', b':wq\r'))
        if got != want:
            print('  arrowcheck   %s in normal mode gave %r, expected %r' % (name, got, want))
            return 1

    print('  arrowcheck   the arrows move the cursor in normal and insert mode')
    return 0


if __name__ == '__main__':
    sys.exit(main())
