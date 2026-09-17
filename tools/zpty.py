"""The two things only a real terminal shows: the window size, and raw mode.

Usage: python3 tools/zpty.py <binary> <outfile>

Zero's behaviour corpus needs no pty (tools/zcases.py): a pipe makes the screen
80x24 by construction, which is the point.  Exactly that is what a pipe cannot
test, so this keeps a handful of pty scenarios and nothing else --

  * the size comes from the terminal.  Two scenarios, 24x80 and 30x100, asking
    `:set lines? columns?`: on a pipe the ioctl fails and the fallback answers
    24 and 80 whatever the pty says, so a run that reports 30 and 100 is the
    ioctl being read;
  * raw mode is entered and left.  Typed text must appear once, not twice: a
    terminal that was never put in raw mode echoes every key itself, and the
    editor's own drawing then lands beside the echo;
  * the arrow keys move in Normal mode, which is a second opinion on
    `tools/nvidxcheck.py` -- a deleted `nv_cmds[]` row under the precomputed
    index is the accident that went twelve whim phases unnoticed, because every
    harness that pressed an arrow pressed it in Insert mode.

**What is recorded is an extraction, not a screen.**  `tools/ptycheck.py` learned
this first: a pty's screen dump is timing-dependent and a recording of it is a
recording of the machine's load.  Each scenario answers a question -- the size,
the term name, the line the editing left -- and the answers are what a baseline
can hold.  The read loop drains until the editor has been quiet, with a hard cap,
because an error at startup leaves it on a Press-ENTER prompt and a loop without
one waits for ever.
"""
import fcntl
import os
import pty
import re
import select
import shutil
import signal
import struct
import sys
import tempfile
import termios
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zrec
import zscreen

ESC = b'\x1b'
DOWN, RIGHT = ESC + b'[B', ESC + b'[C'

SCENARIOS = [
    # name, rows, cols, TERM, keys
    ('size_24x80',  24,  80, 'xterm', [b':set lines? columns?\r', b'\x1b:q!\r']),
    ('size_30x100', 30, 100, 'xterm', [b':set lines? columns?\r', b'\x1b:q!\r']),
    ('raw_typing',  24,  80, 'xterm', [b'ihello world', ESC, b':set term?\r', b'\x1b:q!\r']),
    ('nav_arrows',  24,  80, 'xterm', [b'il1\rl2\rl3', ESC, b'gg', DOWN + DOWN + RIGHT,
                                       b'x', b'\x1b:q!\r']),
]


def session(binary, rows, cols, term, keys, quiet=0.25, cap=3.0, timeout=25.0):
    stage = tempfile.mkdtemp(prefix='zpty-bin-')
    vim = os.path.join(stage, 'vim')                    # argv[0] decides the mode
    shutil.copy2(binary, vim)
    os.chmod(vim, 0o755)
    home = tempfile.mkdtemp(prefix='zpty-home-')
    env = dict(os.environ)
    env.update(TERM=term, HOME=home, VIM=os.path.join(home, 'novim'),
               VIMRUNTIME=os.path.join(home, 'novim'),
               XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)

    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execve(vim, [vim], env)
        finally:
            os._exit(127)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))

    scr = zscreen.Screen(rows, cols)
    deadline = time.time() + timeout

    def settle():
        last = time.time()
        while True:
            now = time.time()
            if now - last > quiet or now > deadline or now - last > cap:
                return True
            r, _, _ = select.select([fd], [], [], 0.02)
            if not r:
                continue
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                return False
            if not chunk:
                return False
            scr.feed(chunk)
            last = time.time()

    alive = settle()
    for k in keys:
        if not alive or time.time() > deadline:
            break
        try:
            os.write(fd, k)
        except OSError:
            break
        alive = settle()
    status = None
    try:
        for _ in range(60):
            w, st = os.waitpid(pid, os.WNOHANG)
            if w:
                status = st
                break
            settle()
        if status is None:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
            status = 'KILLED'
    except ChildProcessError:
        status = 'GONE'
    try:
        os.close(fd)
    except OSError:
        pass
    shutil.rmtree(stage, ignore_errors=True)
    shutil.rmtree(home, ignore_errors=True)
    return scr, status


def answers(scr):
    """The lines a scenario asked for, and the text it left, in a fixed order.

    Every snapshot is searched, not the final screen: the keys that quit wipe the
    message line, so a `:set` answer lives in the redraw before them and nowhere
    else -- the same reason tools/zcases.py records a screen per redraw.
    """
    text = '\n'.join([d for d, _, _, _ in scr.snaps] + [scr.dump()])
    out = []
    for pat in (r'lines=\d+', r'columns=\d+', r'term=[\w.+-]+'):
        out += sorted(set(re.findall(pat, text)))
    body = [l for l in scr.dump().split('\n') if l.strip() and l.strip() != '~']
    return out, body[:3]


def main():
    binary, out = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    rows = []
    for name, r, c, term, keys in SCENARIOS:
        scr, status = session(binary, r, c, term, keys)
        got, body = answers(scr)
        row = '=== %s\n' % name
        row += zrec.section('pty %dx%d TERM=%s status=%s' % (r, c, term, status))
        row += zrec.section('answers', ' '.join(got))
        row += zrec.section('text', ' | '.join(body))
        rows.append(zrec.scrub(row))
    open(out, 'w').write(''.join(rows))
    print('%d pty scenarios -> %s' % (len(SCENARIOS), out))


if __name__ == '__main__':
    main()
