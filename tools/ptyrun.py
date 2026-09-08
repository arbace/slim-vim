"""Drive a real terminal session.

`-e -s` never initialises the terminal, so anything about mappings, screen
drawing, key decoding or `:set` reporting comes back empty from it.  Those need
a pty.

Three things this must get right, all learned the hard way:
  * a hard timeout -- an error at startup leaves vim on a `Press ENTER` prompt
    and a read loop waits for ever;
  * delays between keystrokes -- vim's input parser distinguishes a typed
    Escape from the Escape that starts a key sequence by timing;
  * ANSI escapes stripped from the output before matching, or every comparison
    drowns in cursor positioning.

Importing does nothing.  Call session().
"""
import os
import pty
import re
import select
import shutil
import signal
import tempfile
import time

ANSI = re.compile(rb'\x1b\[[0-9;?]*[a-zA-Z]|\x1b[()][0-9A-B]|\x1b[=>]|\x1b\][^\x07]*\x07|\r')


def session(binary, args, keys, term='xterm', timeout=20.0,
            settle=0.35, cwd=None, env=None):
    """Run `binary` under a pty, type `keys`, return the screen output.

    `keys` is a list of byte strings; each is written then followed by
    `settle` seconds of reading.  Returns (output_bytes_ansi_stripped,
    exit_status).
    """
    # vim reads its own argv[0]: 'r...' is restricted mode, 'e...' evim,
    # 'g...' the GUI.  Stage it under the one name that means plain vim.
    stage = tempfile.mkdtemp(prefix='pty-bin-')
    vim = os.path.join(stage, 'vim')
    shutil.copy2(binary, vim)
    os.chmod(vim, 0o755)

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
    shutil.rmtree(stage, ignore_errors=True)
    return bytes(ANSI.sub(b'', bytes(out))), status
