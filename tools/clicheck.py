#!/usr/bin/env python3
"""Run every command-line option: the dropped ones must be unknown, the rest must work.

Usage:
    python3 tools/clicheck.py <binary>

Written because no harness passed a single option, and that is how three stayed
broken for thirty phases.  `--clean`, `--noplugin` and `--not-a-term` each
matched their own branch of a chain tools/dropopts.py had split, failed every
test after it, and reached `mainerr` anyway -- while behaviour.py, exsweep.py
and termcheck.py all ran `-u NONE -e -s` and nothing else, and agreed.

Every run is `vim <options> f.txt` from a scratch directory of its own, with the
binary staged as `vim`.  A DROPPED option must exit 1 with `Unknown option
argument` naming itself.  A KEPT one must not, and where it has an effect that
`:set`, a file or an exit status can show, that effect is checked: an option that
parses and then does nothing is exactly the failure this exists to catch, so "it
did not complain" is the weakest pass and is used only where nothing stronger can
be observed without a terminal.

EVERY RUN AT ONCE.  The runs are independent -- each has its own directory, so
`-W` and `-w` cannot find each other's files -- and one of them, `-v`, waits two
seconds for a terminal that is not there.  In sequence that wait was paid on top
of fifty-one other launches; concurrently it is the whole cost.

NOT DECIDED HERE: `-y`, `-Z`, `-t` and `-i` go in Phase 18, and `-r` and `-L`
in Phase 21, each with the capability it selected.  At Phase 3 they are still
options, and this says nothing about them either way.
"""

import concurrent.futures
import os
import shutil
import subprocess
import sys
import tempfile

UNKNOWN = 'Unknown option argument: "%s"'

DROPPED = [
    ['-h'], ['-?'], ['--help'], ['--version'],
    ['-A'], ['-F'], ['-H'], ['-g'],
    ['-f'], ['-X'], ['-Y'], ['--nofork'], ['--literal'], ['--gui-dialog-file', 'x'],
    ['--clean'], ['--noplugin'], ['--not-a-term'],
    ['--startuptime', 'st.log'], ['--log', 'x.log'], ['-d', 'x'], ['-U', 'x'], ['-nb'],
    ['-l'], ['-C'], ['-N'], ['-n'], ['-p'], ['-p2'], ['-V'], ['-V9'],
]

EX = ['-e', '-s']

FILES = (('f.txt', 'hello\n'), ('g.txt', 'world\n'), ('s.vim', 'set ts=2\n'),
         ('rc.vim', 'set sw=7\n'), ('keys.in', ''))


def kept():
    """(what, argv, check) -- check takes (rc, output, dir) and returns a complaint or None."""
    def shows(token, rc=0):
        def check(got_rc, out, d):
            if got_rc != rc:
                return 'exit %d, expected %d' % (got_rc, rc)
            if token not in out.split():
                return '%r not in the output' % token
            return None
        return check

    def made(name):
        def check(rc, out, d):
            if rc != 0:
                return 'exit %d, expected 0' % rc
            if not os.path.exists(os.path.join(d, name)):
                return '%s was not written' % name
            return None
        return check

    def accepted(rc, out, d):
        return None if rc == 0 else 'exit %d, expected 0' % rc

    q = lambda cmd: ['-c', cmd, '-c', 'qa!', 'f.txt']
    return [
        ('a file, and nothing else', EX + q('set ts?'), shows('tabstop=4')),
        ('+cmd', EX + ['+set ts=5'] + q('set ts?'), shows('tabstop=5')),
        ('-c', EX + ['-c', 'set ts=3'] + q('set ts?'), shows('tabstop=3')),
        ('--cmd', EX + ['--cmd', 'set sw=6'] + q('set sw?'), shows('shiftwidth=6')),
        ('-S', EX + ['-S', 's.vim'] + q('set ts?'), shows('tabstop=2')),
        ('-u', ['-u', 'rc.vim', '-e', '-s'] + q('set sw?'), shows('shiftwidth=7')),
        ('-b', EX + ['-b'] + q('set bin?'), shows('binary')),
        ('-R', EX + ['-R'] + q('set ro?'), shows('readonly')),
        ('-m', EX + ['-m'] + q('set write?'), shows('nowrite')),
        ('-M', EX + ['-M'] + q('set ma?'), shows('nomodifiable')),
        ('-wN', EX + ['-w7'] + q('set window?'), shows('window=7')),
        ('-E', ['-E', '-s'] + q('set ts?'), shows('tabstop=4')),
        # -v leaves Ex mode, so with no terminal it warns -- which is the proof.
        ('-v', EX + ['-v'] + q('set ts?'), shows('terminal')),
        ('--ttyfail', ['--ttyfail'] + q('set ts?'), shows('terminal', rc=1)),
        ('-W', EX + ['-W', 'w.out'] + q('set ts?'), made('w.out')),
        ('-w file', EX + ['-w', 'a.out'] + q('set ts?'), made('a.out')),
        ('-s file', ['-s', 'keys.in', '-e', '-s'] + q('set ts?'), accepted),
        ('-oN', EX + ['-o2', '-c', 'qa!', 'f.txt', 'g.txt'], accepted),
        ('-ON', EX + ['-O2', '-c', 'qa!', 'f.txt', 'g.txt'], accepted),
        ('-T', EX + ['-T', 'xterm'] + q('set ts?'), accepted),
        ('-', EX + ['-'] + q('set ts?'), accepted),
        ('--', EX + ['-c', 'qa!', '--', 'f.txt'], accepted),
    ]


def run(vim, root, argv):
    """One run, in a directory of its own; returns (rc, output, dir)."""
    d = tempfile.mkdtemp(dir=root)
    for name, content in FILES:
        with open(os.path.join(d, name), 'w') as f:
            f.write(content)
    # No -u NONE: an empty $HOME, $VIM and $VIMRUNTIME are the isolation.  -u
    # itself is still checked below, as an option, at the phase where it exists.
    env = dict(os.environ, HOME=d, VIM=os.path.join(d, 'novim'),
               VIMRUNTIME=os.path.join(d, 'novim'), XDG_CONFIG_HOME=os.path.join(d, 'xdg'))
    for k in ('VIMINIT', 'EXINIT', 'MYVIMRC'):
        env.pop(k, None)
    p = subprocess.run([vim] + argv, cwd=d, stdin=subprocess.DEVNULL, env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       start_new_session=True, timeout=30)
    return p.returncode, p.stdout.decode('utf-8', 'replace'), d


def dropped_case(vim, root, opt):
    rc, out, _ = run(vim, root, ['-e', '-s'] + opt + ['-c', 'qa!', 'f.txt'])
    if rc != 1 or UNKNOWN % opt[0] not in out:
        return 'dropped %-20s exit %d: %s' % (' '.join(opt), rc,
                                               out.strip().replace('\n', ' | ')[:90])
    return None


def kept_case(vim, root, what, argv, check):
    rc, out, d = run(vim, root, argv)
    if 'Unknown option' in out or 'Garbage after option' in out:
        return 'kept    %-20s refused: %s' % (what, out.strip().replace('\n', ' | ')[:90])
    complaint = check(rc, out, d)
    return 'kept    %-20s %s' % (what, complaint) if complaint else None


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    binary = os.path.abspath(sys.argv[1])
    root = tempfile.mkdtemp()
    try:
        # Staged once, as `vim`: the name the binary is called by is not neutral.
        stage = os.path.join(root, 'bin')
        os.mkdir(stage)
        vim = os.path.join(stage, 'vim')
        shutil.copy(binary, vim)
        cases = kept()
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(DROPPED) + len(cases)) as ex:
            futures = [ex.submit(dropped_case, vim, root, opt) for opt in DROPPED]
            futures += [ex.submit(kept_case, vim, root, *c) for c in cases]
            bad = [r for r in (f.result() for f in futures) if r]
    finally:
        shutil.rmtree(root, ignore_errors=True)

    if bad:
        print('  clicheck     %d of %d options wrong:' % (len(bad), len(DROPPED) + len(cases)))
        for b in bad:
            print('                 ' + b)
        sys.exit(1)
    print('  clicheck     %d dropped options unknown, %d kept ones doing what they say'
          % (len(DROPPED), len(cases)))


if __name__ == '__main__':
    main()
