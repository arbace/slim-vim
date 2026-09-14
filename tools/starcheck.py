#!/usr/bin/env python3
"""Does `*` still find the next whole word?

Usage:
    python3 tools/starcheck.py <binary>

Phase 30 keeps `*` and `#` while removing the rest of `nv_ident()`, so this is
the half that has to go on working -- and no behaviour case presses `*`.

**IT HAS TO BE A PTY.**  The first version of this check ran the editor under
`-e -s` and compared the file afterwards, and the two binaries disagreed: before
the phase `:normal *dd` did nothing at all, after it the `*` was ignored and the
`dd` deleted line 1.  Neither is what `*` does.  `normal_search()` wants a
screen, so silent Ex mode measures something that is not the feature -- which is
CLAUDE.md's rule about terminals, mappings and screen drawing needing a real
pty, met once more.

The file is:

    foo          <- the cursor starts here
    bar
    foobar       <- `*` must NOT stop here: not a whole word
    baz
    foo          <- it must stop here

`*` then `dd` deletes whatever it landed on, so the file that comes back says
where it went.  Exits 0 when that is line 5.
"""

import os
import pty
import shutil
import sys
import tempfile
import time

WANT = 'foo bar foobar baz '


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    binary = os.path.abspath(sys.argv[1])
    d = tempfile.mkdtemp()
    try:
        shutil.copy(binary, os.path.join(d, 'vim'))
        with open(os.path.join(d, 'f.txt'), 'w') as fh:
            fh.write('foo\nbar\nfoobar\nbaz\nfoo\n')
        pid, fd = pty.fork()
        if pid == 0:
            os.environ['TERM'] = 'xterm'
            os.chdir(d)
            os.execv('./vim', ['vim', '-u', 'NONE', 'f.txt'])
            os._exit(127)
        time.sleep(0.9)
        for keys in (b'*', b'dd', b':wq\r'):
            os.write(fd, keys)
            time.sleep(0.4)
        time.sleep(0.9)
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
        os.close(fd)
        got = open(os.path.join(d, 'f.txt')).read().replace('\n', ' ')
    finally:
        shutil.rmtree(d, ignore_errors=True)
    if got != WANT:
        print('  starcheck    * gave %r, expected %r' % (got, WANT))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
