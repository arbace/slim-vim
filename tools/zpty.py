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
can hold.

**A KEY IS TYPED WHEN THE REDRAW BEFORE IT HAS ENDED, NOT WHEN A CLOCK SAYS SO.**
This used to wait for the editor to be quiet for a quarter of a second and then
write the next key.  A quiet period is a reading of the machine's load: under
enough of one the editor stalls mid-redraw for longer than that, the next key
goes in early, and the answer the scenario asked for is wiped by the keys that
quit before any redraw ever ended on it.  Measured on the r1 binary against the
recorded baselines: 1 of 30 runs under a steady 64-way load and 3 of 30 under an
oscillating 128-way one, every failure the same one -- `size_30x100`'s `answers`
block empty where the baseline holds `lines=30 columns=100`, because `:set lines?
columns?` was answered into a screen no `\x1b[?25h` ever closed.  A longer quiet
would move that boundary and not remove it, which is what b66e982 established for
the sibling defect in the `:q!` probes.

So the wait is for CONTENT, and `tools/zscreen.py` already says what content:
`\x1b[?25h` -- show cursor -- is where a redraw ENDS, because the editor hides
the cursor while it draws and shows it when the screen is settled and it is about
to wait for a key.  `settle()` counts those in the byte stream and returns when
one MORE has arrived than had before the key was written, and only then asks
whether output has gone quiet.  The quiet period itself is unchanged at 0.25 s;
what changed is that it is never asked about until a redraw has ended.  Measured
on the four scenarios, every key produces at least one: startup 1, and
`(1,1,2)`, `(1,1,2)`, `(1,2,2,1,1)`, `(1,2,2,1,3,2,1)` for the four.

**The deadline is the failure path and it says so.**  A run that never sees its
redraw end, or an editor that never exits, used to return a short capture
silently -- and under a heavy enough load the old exit poll (`for _ in range(60):
waitpid(WNOHANG); settle()`) spun through all sixty iterations in no time once
the deadline had passed and SIGKILLed a live editor, recording `status=KILLED`.
Now the exit is waited for on content too -- the pty master reads EIO when the
child has closed its end -- and anything that reaches the deadline is written
into the record as a `stalled` section, printed on stderr, and makes this tool
exit non-zero.  A harness that cannot answer must say so, not answer shortly.
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
import zstream

ESC = b'\x1b'
DOWN, RIGHT = ESC + b'[B', ESC + b'[C'
# tools/zscreen.py snapshots here, and for the same reason this waits here.
SHOW_CURSOR = b'\x1b[?25h'

SCENARIOS = [
    # name, rows, cols, TERM, keys
    ('size_24x80',  24,  80, 'xterm', [b':set lines? columns?\r', b'\x1b:q!\r']),
    ('size_30x100', 30, 100, 'xterm', [b':set lines? columns?\r', b'\x1b:q!\r']),
    ('raw_typing',  24,  80, 'xterm', [b'ihello world', ESC, b':set term?\r', b'\x1b:q!\r']),
    ('nav_arrows',  24,  80, 'xterm', [b'il1\rl2\rl3', ESC, b'gg', DOWN + DOWN + RIGHT,
                                       b'x', b'\x1b:q!\r']),
]


def session(binary, rows, cols, term, keys, quiet=0.25, timeout=60.0):
    """Run the editor under a pty, type `keys`, return (screen, status, stalled).

    `stalled` is the list of waits that reached the deadline instead of their
    content, and is empty on every run that answered.  `timeout` is generous
    because it is the failure path: 25 s used to be reached by an ordinary run
    on a loaded machine, which is how a clock came to decide a recording.
    """
    vim = zstream.stage(binary)     # argv[0], and the copy race: tools/zstream.py
    home = tempfile.mkdtemp(prefix='zpty-home-')
    env = dict(os.environ)
    env.update(TERM=term, HOME=home, VIM=os.path.join(home, 'novim'),
               VIMRUNTIME=os.path.join(home, 'novim'),
               XDG_CONFIG_HOME=os.path.join(home, 'xdg'))
    for k in ('LINES', 'COLUMNS', 'VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)

    # THE WINDOW IS THE RIGHT SIZE BEFORE THE EDITOR EXISTS, and that is the second
    # race here rather than a tidiness.  This used to set TIOCSWINSZ on the master
    # AFTER pty.fork() returned, which is a bet that the parent's ioctl beats the
    # child's startup.  Under load it loses: the editor comes up believing the
    # screen is 24x80, sets a 24-row scroll region (`\x1b[1;24r`), and when the
    # SIGWINCH finally arrives the region is still 24 rows while the screen is 30 --
    # so `:set lines? columns?` writes `  lines=30`, `  columns=100` and the
    # Press-ENTER prompt onto the SAME bottom row, each overwriting the last, and the
    # recording's `answers` block comes back empty.  Caught in the act: a failing
    # 3,545-byte stream holds `lines=` and `columns=` and its Press-ENTER snapshot
    # holds neither, with `\x1b[1;24r` earlier in the same stream.  The child sets
    # the size on its own controlling terminal before it execs, which cannot lose.
    pid, fd = pty.fork()
    if pid == 0:
        try:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
            os.execve(vim, [vim], env)
        finally:
            os._exit(127)

    scr = zscreen.Screen(rows, cols)
    seen = bytearray()                  # every byte, only to count the redraws in it
    deadline = time.time() + timeout
    stalled = []

    def read_once():
        """One read.  False once the editor is gone: the master gives EIO then."""
        r, _, _ = select.select([fd], [], [], 0.02)
        if not r:
            return True
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            return False
        if not chunk:
            return False
        seen.extend(chunk)
        scr.feed(chunk)
        return True

    def settle(what):
        """Wait for one more redraw to END, and only then for the output to stop.

        The content half is the whole of the fix: a quiet period alone is a
        reading of the machine's load, and asking about it before a redraw has
        ended is what typed the next key into a screen that was still being
        drawn.  `quiet` is still 0.25 s and now only mops up the rest of a burst.
        """
        want = seen.count(SHOW_CURSOR) + 1
        last = time.time()
        while True:
            n = len(seen)
            alive = read_once()
            if len(seen) > n:
                last = time.time()
            if not alive:
                return False
            now = time.time()
            if seen.count(SHOW_CURSOR) >= want and now - last > quiet:
                return True
            if now > deadline:
                stalled.append(what)
                return True

    alive = settle('startup')
    for i, k in enumerate(keys):
        if not alive:
            break
        try:
            os.write(fd, k)
        except OSError:
            break
        alive = settle('key %d (%r)' % (i, k))
    # THE EDITOR IS GONE WHEN ITS END OF THE PTY IS, which is content as well: the
    # master read fails with EIO once the child has closed it.  What was here
    # instead was sixty WNOHANG polls with a settle between them, and once the
    # deadline had passed a settle returned at once -- so the sixty ran through in
    # no time and SIGKILLed a live editor, recording `status=KILLED`.
    while alive and time.time() <= deadline:
        alive = read_once()
    try:
        if alive:
            stalled.append('exit')
            os.kill(pid, signal.SIGKILL)
        _, status = os.waitpid(pid, 0)
    except ChildProcessError:
        status = 'GONE'
    try:
        os.close(fd)
    except OSError:
        pass
    shutil.rmtree(home, ignore_errors=True)
    return scr, status, stalled


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
    rows, bad = [], []
    for name, r, c, term, keys in SCENARIOS:
        scr, status, stalled = session(binary, r, c, term, keys)
        got, body = answers(scr)
        row = '=== %s\n' % name
        row += zrec.section('pty %dx%d TERM=%s status=%s' % (r, c, term, status))
        row += zrec.section('answers', ' '.join(got))
        row += zrec.section('text', ' | '.join(body))
        # A WAIT THAT REACHED ITS DEADLINE SAYS SO, in the record and on stderr and
        # in the exit status.  Returning the short capture silently is what made
        # this a recording of the machine's load rather than of the editor.
        if stalled:
            row += zrec.section('stalled', '; '.join(stalled))
            bad.append('%s: %s' % (name, '; '.join(stalled)))
        rows.append(zrec.scrub(row))
    open(out, 'w').write(''.join(rows))
    if bad:
        sys.stderr.write('zpty.py: NO REDRAW ENDED INSIDE THE DEADLINE -- this '
                         'recording is of the machine and not of %s\n' % binary)
        for b in bad:
            sys.stderr.write('  %s\n' % b)
        sys.exit(1)
    print('%d pty scenarios -> %s' % (len(SCENARIOS), out))


if __name__ == '__main__':
    main()
