"""What the command line accepts: one invocation each, recorded.

Usage: python3 tools/zargv.py <binary> <outfile>

argv is not keystrokes, so it needs an instrument of its own -- `tools/clicheck.py`
in stream form.  Every invocation gets the same keystroke file (quit at once) and
is recorded by exit status, stderr, and how many bytes of screen it drew, which
is how "it started and then quit" is told from "it refused before drawing".

It is the only instrument that can see a command-line phase: `+{command}` and
`-T {term}` are what argv ends as (ZERO-PLAN.md P4), and every option on the way
out -- `-e`, `-E`, `-s`, `-v`, bare `-`, `--` -- is a row here and nowhere else.

`vim -` blocks: it reads the keystroke FILE as buffer text, closes fd 0, dups
stderr and waits there for keys that never come.  That is a recording, not a
crash (tools/zstream.py), and it costs the timeout each run.
"""
import concurrent.futures
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zrec
import zstream

KEYS = [b'\x1b:q!\r']

INVOCATIONS = [
    [], ['+q!'], ['+set nu', '+q!'], ['+set nu'],
    ['-T', 'xterm'], ['-T'], ['-Txterm'], ['-T', 'no-such-term-9x'],
    ['-e'], ['-E'], ['-e', '-s'], ['-v'], ['-'], ['--'], ['--ttyfail'],
    ['-R'], ['-c', 'q!'], ['-u', 'NONE'], ['-i', 'NONE'], ['-m'], ['-Z'], ['-y'],
    ['f.txt'], ['f.txt', 'g.txt'], ['--version'], ['--help'], ['-h'],
    ['+'], ['+q!', 'f.txt'], ['--', '+q!'],
]


def one(args, binary):
    name = ' '.join(args) if args else '(none)'
    row = '=== %s\n' % name
    try:
        scr, out, err, rc = zstream.session(binary, KEYS, args=args, timeout=5)
    except zstream.Blocked:
        return row + zrec.section('blocked', 'took the input over and never returned')
    row += zrec.section('exit %s' % rc)
    row += zrec.section('stream %d' % len(out))
    row += zrec.section('stderr', err.decode('utf-8', 'replace').rstrip('\n'))
    return zrec.scrub(row)


def main():
    binary, out = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    t = time.time()
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(INVOCATIONS)) as ex:
        rows = list(ex.map(lambda a: one(a, binary), INVOCATIONS))
    open(out, 'w').write(''.join(rows))
    print('%d invocations -> %s in %.1fs' % (len(rows), out, time.time() - t))


if __name__ == '__main__':
    main()
