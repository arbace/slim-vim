"""Dispatch every Ex command name once and record what happened.

Run from a scratch directory, always.  `:mkvimrc`, `:mkexrc`, `:mksession`,
`:mkview` and `:wviminfo` with no argument write into the cwd; a previous run
did this from the repository root, committed two of the files by accident, and
made the sweep lie in both directions -- with the files already present those
two commands returned 1 instead of 0, so a comparison against a reference
recorded the same way agreed for the wrong reason.

Usage: exsweep.py <vim-binary> <ex_cmds.h|vim.c> <outfile>
"""
import concurrent.futures
import os
import shutil
import subprocess
import sys
import tempfile

_HOME = tempfile.mkdtemp(prefix="exsweep-home-")
import atexit
atexit.register(shutil.rmtree, _HOME, True)
# No -u NONE.  An empty $HOME, $VIM and $VIMRUNTIME are the isolation instead:
# slim-vim finds no ~/.vimrc, system vimrc or runtime defaults in them, and
# whim-vim, which has no -u from its Phase 18, looks for none of them anyway.
ENV = dict(os.environ, HOME=_HOME, VIM=os.path.join(_HOME, "novim"),
           VIMRUNTIME=os.path.join(_HOME, "novim"), XDG_CONFIG_HOME=os.path.join(_HOME, "xdg"))
for _k in ("VIMINIT", "EXINIT", "MYVIMRC"):
    ENV.pop(_k, None)

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

    # How a run quits.  :qall! closes every window a command opened, which is what
    # makes :new, :split and the rest deterministic in slim-vim.  whim-vim has one
    # window from its Phase 39 and no :qall from its Phase 46, and there :q! is the
    # same thing.  Asked of the binary once, rather than assumed from its name.
    probe = subprocess.run([vim, '-e', '-s', '+qall!'], stdin=subprocess.DEVNULL,
                           capture_output=True, env=ENV, cwd=_HOME, timeout=20)
    quit_cmd = '+qall!' if probe.returncode == 0 else '+q!'

    # These hand control to another program or to the job-control signal
    # machinery; their result is the environment's, not the editor's, and it
    # is not reproducible from one run to the next.
    SKIP = {'shell', 'suspend', 'stop', 'terminal', 'gui', 'gvim'}

    def one(name):
        if name in SKIP:
            return '%-24s SKIPPED (hands over the terminal)' % name
        d = tempfile.mkdtemp(prefix='exsweep-')
        try:
            src = os.path.join(d, 'f.txt')
            open(src, 'w').write('alpha\nbeta\ngamma\n')
            # +{command}, not -c: see tools/behaviour.py.
            r = subprocess.run(
                [vim, '-e', '-s',
                 '+' + name, quit_cmd, src],
                stdin=subprocess.DEVNULL, capture_output=True, env=ENV,
                cwd=d, timeout=20,
                # :suspend / :stop signal the whole process group with SIGTSTP.
                # Without a session of its own the sweep stops its own shell,
                # which looks like the harness crashing at command 500.
                start_new_session=True)
            err = r.stderr.decode('utf-8', 'replace').strip().replace('\n', ' | ')
            # Files a command left behind in the cwd are part of what it did.
            left = sorted(x for x in os.listdir(d) if x != 'f.txt')
            return ('%-24s exit=%-3d left=%-40s err=%s'
                    % (name, r.returncode, ','.join(left) or '-', err))
        except subprocess.TimeoutExpired:
            return '%-24s TIMEOUT' % name
        finally:
            shutil.rmtree(d, ignore_errors=True)

    # EVERY COMMAND AT ONCE, in rows kept in table order.  Each dispatch has its
    # own scratch directory and its own session, so nothing one command does can
    # reach another -- which the sweep already required, to keep :mkvimrc's file
    # out of the next command's listing -- and map() returns in submission order,
    # so the recording is the same bytes it always was.
    with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count() or 1) as ex:
        rows = list(ex.map(one, names))

    shutil.rmtree(stage, ignore_errors=True)
    open(out, 'w').write('\n'.join(rows) + '\n')
    print(len(rows), 'commands ->', out)


if __name__ == '__main__':
    main()
