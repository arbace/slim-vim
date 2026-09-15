#!/usr/bin/env python3
"""Insert mode still inserts, and CTRL-N no longer completes.

Usage:
    python3 tools/complcheck.py <binary>

Phase 32 stubs the five predicates the completion subsystem hangs from, so two
things have to be true afterwards and only the pair is a check: ordinary insert
mode must be untouched, and CTRL-N must insert nothing rather than completing.

**IT HAS TO BE A PTY.**  A popup menu needs a screen, and `ins_complete()` is
reached through `edit()`'s key loop; under `-e -s` neither half of this means
anything, which is the mistake `tools/starcheck.py` records for `*`.

The buffer starts as

    alpha
    al

with the cursor left at the end of the second line.  Typing CTRL-N there used to
complete `al` to `alpha` from the current file.  It must now leave the line as
`al`, while the same insert that types `X` must still produce `alX`.
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
            fh.write('alpha\nal\n')
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


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    b = os.path.abspath(sys.argv[1])

    # the control: an ordinary insert at the end of line 2
    got = run(b, (b'G', b'A', b'X', b'\x1b', b':wq\r'))
    if got != 'alpha alX ':
        print('  complcheck   plain insert gave %r, expected %r' % (got, 'alpha alX '))
        return 1

    # and CTRL-X CTRL-N, which used to complete `al` to `alpha`.
    #
    # NOT BARE CTRL-N: measured on the binary before the phase, CTRL-N inserts
    # nothing at all in this fork -- the screen says `-- INSERT --` and the
    # cursor does not move -- so a check written on it passes before and after
    # and proves nothing.  CTRL-X CTRL-N does complete today, which is what
    # makes it a check.
    got = run(b, (b'G', b'A', b'\x18\x0e', b'\x1b', b':wq\r'))
    if got != 'alpha al ':
        print('  complcheck   CTRL-X CTRL-N gave %r, expected %r -- it should '
              'complete nothing now' % (got, 'alpha al '))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
