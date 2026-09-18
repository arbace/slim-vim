"""Drive the editor with a keystroke FILE on stdin and keep what it drew.

Keystrokes in, screen out, and no pty: stdin is a file of keys, stdout a file of
escape sequences, and `tools/zscreen.py` turns the second into a screen.  There
is nothing to settle, no ANSI to strip, no Press-ENTER hazard and no timing --
the editor reads every key as fast as it can and exits, and the bytes it wrote
are the whole recording.  The terminal is 80x24 by construction: the window-size
ioctl fails on a pipe and the editor's built-in fallback applies, and `$LINES`
and `$COLUMNS` have decided nothing since whim's Phase 19.

Three things it must get right, all of them measured (ZERO-PLAN.md 2b, 2l):

  * **a session of its own.**  `:stop` and `:suspend` signal the process GROUP
    with SIGTSTP; without `start_new_session` the command sweep stopped the shell
    that ran it -- exit 148, which reads like the harness dying at command 100;
  * **a timeout, and a recording for what hits it.**  `vim -` reads the keystroke
    FILE as buffer text, then closes fd 0 and dups stderr, and waits there for
    keys that never come.  An invocation that blocks is a recording, not a crash;
  * **argv[0].**  A binary whose name begins with `r` is restricted mode, `e` is
    evim, `g` the GUI: every run is staged as `vim`, whatever it was called.
    `stage()` below is the one place that does it, for this tool and for every zero
    phase check, and it is one place because of a race and not for tidiness.

Importing does nothing.  Call `session()`.
"""
import atexit
import os
import shutil
import subprocess
import tempfile
import threading

import zscreen


class Blocked(Exception):
    """The editor took the input over and did not return."""


_staged = {}
_staging = threading.Lock()


def stage(binary):
    """The binary under the one name that means plain vim.  Every harness uses this.

    argv[0] is why it is renamed (CLAUDE.md); a race is why it is ONE function.
    `shutil.copy2` holds a write fd on its destination while it copies, and a `fork`
    in ANOTHER thread -- every harness here runs its cases in a ThreadPoolExecutor --
    hands that thread's child the same fd until it execs.  `execve` refuses a file
    any process holds open for writing, so the COPYING thread's own exec then dies
    with `OSError: [Errno 26] Text file busy`, the case it was written for never
    runs, and the harness writes an empty record and exits non-zero.  Measured on the
    r1 binary: 0 of 20 runs of zcases.py/zargv.py failed that way idle and **8 of
    20** under a steady 64-way load, and a `make zero-verify` under that load lost 15
    of its 18 units, almost every one of them this and not the pty -- and three
    verify runs on an ORDINARY busy machine lost four, three and three, every one of
    them a phase check's own copy of the three lines this replaces.

    Two things make it safe, and neither is a retry.  **The copy happens once per
    binary**, under a lock, so 102 sessions do not make 102 windows.  And **it
    happens in a child process**, so the write fd exists in `cp` and never in this
    address space -- a thread forking at the same instant cannot inherit what we do
    not hold.  That is what makes it correct however late a caller asks for it,
    which a lock alone is not: `pipes/zero4-check.sh` stages a SECOND binary from
    inside the pool that is already forking the first.
    """
    with _staging:
        vim = _staged.get(binary)
        if vim is None:
            d = tempfile.mkdtemp(prefix='zstream-bin-')
            vim = os.path.join(d, 'vim')
            subprocess.run(['cp', binary, vim], check=True)
            os.chmod(vim, 0o755)
            atexit.register(shutil.rmtree, d, True)
            _staged[binary] = vim
        return vim


def session(binary, keys, term='xterm', args=(), rows=24, cols=80, timeout=20):
    """Run `binary` with `keys` on stdin.  Returns (screen, stdout, stderr, rc)."""
    vim = stage(binary)
    home = tempfile.mkdtemp(prefix='zstream-home-')
    env = dict(os.environ)
    env.update(TERM=term, HOME=home, VIM=os.path.join(home, 'novim'),
               VIMRUNTIME=os.path.join(home, 'novim'),
               XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    d = tempfile.mkdtemp(prefix='zstream-run-')
    kf = os.path.join(d, 'keys')
    with open(kf, 'wb') as f:
        f.write(b''.join(keys))
    try:
        with open(kf, 'rb') as stdin:
            try:
                r = subprocess.run([vim] + list(args), stdin=stdin,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   env=env, cwd=d, timeout=timeout,
                                   start_new_session=True)
            except subprocess.TimeoutExpired:
                raise Blocked()
        scr = zscreen.Screen(rows, cols)
        scr.feed(r.stdout)
        return scr, r.stdout, r.stderr, r.returncode
    finally:
        shutil.rmtree(home, ignore_errors=True)
        shutil.rmtree(d, ignore_errors=True)
