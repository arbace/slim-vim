"""Every Ex command name, typed at `:`, and what the editor said.

Usage: python3 tools/zexcmds.py <binary> <source> <outfile>

`tools/exsweep.py` recorded three things zero does not have: an exit status worth
reading (the editor is quit by the harness, not by the command), the files left
in the cwd, and stderr.  What is left is what the editor SAYS, and the message
line is recordable because `tools/zscreen.py` snapshots every redraw -- with only
the final screen, every row here read `~`, because the keys that quit wipe the
message (measured).

So a row is the screen after the command: the text at the top, and every distinct
message line from the command onwards.  That is a message-level record where the
old one was an exit status -- retiring `:write` moves `E32: No file name` to
`E492: Not an editor command`, which the file sweep could not have seen, both
being exit 1.

Two things it had to be taught, both measured (ZERO-PLAN.md 2i):

  * `:highlight` pages, and ESC does not stop a `--More--` listing -- the session
    then ran to the timeout.  `q` ends it, and in Normal mode `q` followed by ESC
    is an aborted recording that changes nothing.  (`.` also works and repeats
    the last change, which polluted the row.)
  * `:stop` and `:suspend` hand the process group to the shell; they are skipped
    here as they are in the file sweep, and every run gets a session of its own
    anyway (tools/zstream.py).
"""
import concurrent.futures
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import create_cmdidxs as cmdidxs
import zrec
import zstream

SEED = b'alpha\rbeta\rgamma'
SKIP = {'stop', 'suspend'}


def one(args):
    name, binary = args
    if name in SKIP:
        return '=== %s\n%s' % (name, zrec.section('skipped', 'hands over the process group'))
    keys = [b'i' + SEED + b'\x1b', b':set nopaste\r',
            b':' + name.encode() + b'\r',
            b'q', b'\x1b', b':q!\r']
    try:
        scr, out, err, rc = zstream.session(binary, keys, args=['+set paste'])
    except zstream.Blocked:
        return '=== %s\n%s' % (name, zrec.section('blocked', 'never returned'))
    text = ''
    msgs = []
    for i, (dump, y, x, bells) in enumerate(scr.snaps):
        lines = dump.split('\n')
        # The seed and the `:set nopaste` make the first snapshots; from the
        # command's own onwards, the top of the screen and every distinct last row.
        if i >= 2:
            if not text:
                text = ' | '.join(l for l in lines[:6] if l.strip() and l.strip() != '~')
            m = lines[-1].rstrip()
            if m and m not in msgs:
                msgs.append(m)
    row = '=== %s\n' % name
    row += zrec.section('exit %s' % rc)
    row += zrec.section('bells %d' % scr.bells)
    row += zrec.section('stderr', err.decode('utf-8', 'replace').rstrip('\n'))
    row += zrec.section('text', text)
    row += zrec.section('msgs', '\n'.join(msgs))
    return zrec.scrub(row)


def main():
    binary, table, out = (os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2]),
                          os.path.abspath(sys.argv[3]))
    names = cmdidxs.names(table)
    t = time.time()
    with concurrent.futures.ThreadPoolExecutor(
            max_workers=min(len(names), (os.cpu_count() or 4) * 2)) as ex:
        rows = list(ex.map(one, [(n, binary) for n in names]))
    open(out, 'w').write(''.join(rows))
    print('%d commands -> %s in %.1fs' % (len(rows), out, time.time() - t))


if __name__ == '__main__':
    main()
