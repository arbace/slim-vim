"""Drive a real terminal session.

`-e -s` never initialises the terminal, so anything about mappings, screen
drawing, key decoding or `:set` reporting comes back empty from it.  Those need
a pty.

Four things this must get right, all learned the hard way:
  * a hard timeout -- an error at startup leaves vim on a `Press ENTER` prompt
    and a read loop waits for ever;
  * delays between keystrokes -- vim's input parser distinguishes a typed
    Escape from the Escape that starts a key sequence by timing;
  * ANSI escapes stripped from the output before matching, or every comparison
    drowns in cursor positioning;
  * staging the binary as `vim` -- argv[0] decides what the editor IS -- and
    staging it in a way that a thread pool cannot race.  See stage().

Importing does nothing.  Call session().
"""
import atexit
import os
import pty
import re
import select
import shutil
import signal
import subprocess
import tempfile
import threading
import time

ANSI = re.compile(rb'\x1b\[[0-9;?]*[a-zA-Z]|\x1b[()][0-9A-B]|\x1b[=>]|\x1b\][^\x07]*\x07|\r')

_staged = {}
_staging = threading.Lock()


def stage(binary):
    """The binary under the one name that means plain vim.  Every session uses this.

    argv[0] is why it is renamed: 'r...' is restricted mode, 'e...' evim, 'g...'
    the GUI, and only a basename of `vim` is plain vim.  A RACE is why it is one
    function and not three lines inside session().  `shutil.copy2` holds a write fd
    on its destination while it copies, and a `fork` in ANOTHER thread -- termcheck.py
    runs nineteen sessions in a ThreadPoolExecutor and ptycheck.py five -- hands that
    thread's child the same fd until it execs.  `execve` refuses a file any process
    holds open for writing, so the COPYING thread's own exec then dies with
    `OSError: [Errno 26] Text file busy`, the session it was written for never runs,
    and the caller gets an empty capture.  Measured here, through termcheck.py and
    with the child's exec failure logged rather than swallowed: **5 in 100 idle runs**
    (1,900 pty sessions), every one errno 26, against **0 in 100** with this staging;
    and interleaved in one loop so ambient conditions cannot favour either, **1 of 60
    against 0 of 60**.  Load does NOT make it likelier -- 0 in 60 runs under a steady
    256-way spin load and 0 in 20 under an oscillating 128-way one -- because what
    overlaps is the nineteen threads' startup, which a loaded machine spreads apart.
    None of the six moved a recording, because termcheck.py retries an empty answer at
    a longer settle; the zero phase checks that called session() directly had no such
    ladder, and an empty capture there was a failed check.

    Two things make it safe, and neither is a retry.  **The copy happens once per
    binary**, under a lock, so nineteen sessions do not make nineteen windows.  And
    **it happens in a child process**, so the write fd exists in `cp` and never in
    this address space -- a thread forking at the same instant cannot inherit what we
    do not hold.  That is what makes it correct however late a caller asks for it,
    which a lock alone is not: a caller may stage a SECOND binary from inside a pool
    already forking the first.

    **The zero pipeline's `zstream.py` carried a copy of this `stage()`**, kept
    apart for the cache keys: `tools/implhash.sh` follows one level of named paths,
    `pipes/slim1.sh` names `tools/termcheck.py` and `termcheck.py` names this file,
    so an import would have put a zero tool inside slim's implementation keys.  Both
    pipelines now live in github.com/arbace/go-whim, in Go.
    """
    with _staging:
        vim = _staged.get(binary)
        if vim is None:
            d = tempfile.mkdtemp(prefix='pty-bin-')
            vim = os.path.join(d, 'vim')
            subprocess.run(['cp', binary, vim], check=True)
            os.chmod(vim, 0o755)
            atexit.register(shutil.rmtree, d, True)
            _staged[binary] = vim
        return vim


def session(binary, args, keys, term='xterm', timeout=20.0,
            settle=0.35, cwd=None, env=None):
    """Run `binary` under a pty, type `keys`, return the screen output.

    `keys` is a list of byte strings; each is written then followed by
    `settle` seconds of reading.  Returns (output_bytes_ansi_stripped,
    exit_status).
    """
    vim = stage(binary)

    e = dict(os.environ if env is None else env)
    e['TERM'] = term
    e.pop('LINES', None)
    e.pop('COLUMNS', None)

    pid, fd = pty.fork()
    if pid == 0:                                    # child
        try:
            if cwd:
                os.chdir(cwd)
            os.execve(vim, [vim] + list(args), e)
        finally:
            os._exit(127)

    out = bytearray()
    deadline = time.time() + timeout

    def drain(until):
        while time.time() < until:
            r, _, _ = select.select([fd], [], [], 0.05)
            if not r:
                continue
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                return False
            if not chunk:
                return False
            out.extend(chunk)
        return True

    drain(min(time.time() + settle * 2, deadline))
    for k in keys:
        if time.time() > deadline:
            break
        try:
            os.write(fd, k)
        except OSError:
            break
        drain(min(time.time() + settle, deadline))

    status = None
    try:
        for _ in range(int((deadline - time.time()) / 0.1) + 1):
            wpid, st = os.waitpid(pid, os.WNOHANG)
            if wpid:
                status = st
                break
            drain(time.time() + 0.1)
        if status is None:
            os.kill(pid, signal.SIGKILL)
            _, status = os.waitpid(pid, 0)
    except ChildProcessError:
        status = -1
    try:
        os.close(fd)
    except OSError:
        pass
    return bytes(ANSI.sub(b'', bytes(out))), status
