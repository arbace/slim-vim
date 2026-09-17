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

Importing does nothing.  Call `session()`.
"""
import os
import shutil
import subprocess
import tempfile

import zscreen


class Blocked(Exception):
    """The editor took the input over and did not return."""


def session(binary, keys, term='xterm', args=(), rows=24, cols=80, timeout=20):
    """Run `binary` with `keys` on stdin.  Returns (screen, stdout, stderr, rc)."""
    stage = tempfile.mkdtemp(prefix='zstream-bin-')
    vim = os.path.join(stage, 'vim')
    shutil.copy2(binary, vim)
    os.chmod(vim, 0o755)
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
        shutil.rmtree(stage, ignore_errors=True)
        shutil.rmtree(home, ignore_errors=True)
        shutil.rmtree(d, ignore_errors=True)
