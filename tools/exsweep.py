"""Dispatch every Ex command name once and record what happened.

Run from a scratch directory, always.  `:mkvimrc`, `:mkexrc`, `:mksession`,
`:mkview` and `:wviminfo` with no argument write into the cwd; a previous run
did this from the repository root, committed two of the files by accident, and
made the sweep lie in both directions -- with the files already present those
two commands returned 1 instead of 0, so a comparison against a reference
recorded the same way agreed for the wrong reason.

Usage: exsweep.py <vim-binary> <ex_cmds.h|vim.c> <outfile>
"""
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import create_cmdidxs as cmdidxs


def main():
    binary = os.path.abspath(sys.argv[1])
    table = os.path.abspath(sys.argv[2])
    out = os.path.abspath(sys.argv[3])

    names = cmdidxs.names(table)

    # vim reads its own argv[0]; see the note in behaviour.py.  Stage it as "vim".
    stage = tempfile.mkdtemp(prefix='exsweep-bin-')
    vim = os.path.join(stage, 'vim')
    shutil.copy2(binary, vim)
    os.chmod(vim, 0o755)

    # These hand control to another program or to the job-control signal
    # machinery; their result is the environment's, not the editor's, and it
    # is not reproducible from one run to the next.
    SKIP = {'shell', 'suspend', 'stop', 'terminal', 'gui', 'gvim'}

    rows = []
    for name in names:
        if name in SKIP:
            rows.append('%-24s SKIPPED (hands over the terminal)' % name)
            continue
        d = tempfile.mkdtemp(prefix='exsweep-')
        try:
            src = os.path.join(d, 'f.txt')
            open(src, 'w').write('alpha\nbeta\ngamma\n')
            r = subprocess.run(
                [vim, '-u', 'NONE', '-e', '-s',
                 '-c', name, '-c', 'qall!', src],
                stdin=subprocess.DEVNULL, capture_output=True,
                cwd=d, timeout=20,
                # :suspend / :stop signal the whole process group with SIGTSTP.
                # Without a session of its own the sweep stops its own shell,
                # which looks like the harness crashing at command 500.
                start_new_session=True)
            err = r.stderr.decode('utf-8', 'replace').strip().replace('\n', ' | ')
            # Files a command left behind in the cwd are part of what it did.
            left = sorted(x for x in os.listdir(d) if x != 'f.txt')
            rows.append('%-24s exit=%-3d left=%-40s err=%s'
                        % (name, r.returncode, ','.join(left) or '-', err))
        except subprocess.TimeoutExpired:
            rows.append('%-24s TIMEOUT' % name)
        finally:
            shutil.rmtree(d, ignore_errors=True)

    shutil.rmtree(stage, ignore_errors=True)
    open(out, 'w').write('\n'.join(rows) + '\n')
    print(len(rows), 'commands ->', out)


if __name__ == '__main__':
    main()
