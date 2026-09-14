#!/usr/bin/env python3
"""Does a killed editor put the terminal back?

Usage:
    python3 tools/termrestore.py <binary>

This is the single thing Phase 29 keeps SIGHUP and SIGTERM for, and no harness
here asks it.  The behaviour cases and the Ex sweep run the editor to
completion; the pty harness types keys and quits cleanly.  None of them kills
one halfway and then looks at the terminal.

So: open a pty, start the editor on it, let it get as far as raw mode, send
SIGTERM, and read the terminal's attributes back.  `deathtrap()` ->
`preserve_exit()` -> `prepare_to_exit()` runs `settmode(TMODE_COOK)`, which puts
ICANON and ECHO back.  If they are still off, the user's shell is unusable and
they have to type `reset` blind -- which is a worse failure than a crash, and
the reason the handler is worth its symbols.

Exits 0 if the terminal came back cooked.
"""

import os
import pty
import signal
import sys
import termios
import time


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    binary = os.path.abspath(sys.argv[1])

    pid, fd = pty.fork()
    if pid == 0:
        os.environ['TERM'] = 'xterm'
        os.chdir('/tmp')
        os.execv(binary, [binary, '-u', 'NONE'])
        os._exit(127)

    # let it reach raw mode, and check that it really did -- otherwise the test
    # passes for the wrong reason, on an editor that never changed anything
    time.sleep(1.2)
    try:
        raw = termios.tcgetattr(fd)
    except Exception as e:
        print('  termrestore  cannot read the pty: %s' % e)
        os.kill(pid, signal.SIGKILL)
        return 1
    if raw[3] & termios.ICANON or raw[3] & termios.ECHO:
        print('  termrestore  the editor never put the terminal in raw mode, so'
              ' this proves nothing')
        os.kill(pid, signal.SIGKILL)
        return 1

    os.kill(pid, signal.SIGTERM)
    for _ in range(50):
        time.sleep(0.1)
        try:
            os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            break
        try:
            now = termios.tcgetattr(fd)
        except Exception:
            break
        if now[3] & termios.ICANON and now[3] & termios.ECHO:
            os.close(fd)
            return 0
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    print('  termrestore  ICANON/ECHO were still off after SIGTERM')
    return 1


if __name__ == '__main__':
    sys.exit(main())
