"""What each TERM resolves to, and how many colours it gets."""
import concurrent.futures
import os, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# The import below reaches a tool that tools/implhash.sh would otherwise not see.
# implhash extracts dependencies by grepping for tools/ PATHS, and an `import`
# names a module, not a path -- so tools/ptyrun.py sat in no implementation key and an
# edit to it would have moved no cache key at all.  Naming the path here is what
# puts it back in this phase's key; implhash greps, and does not know what a
# comment is.  Do not delete this line without reading CLAUDE.md on the gap.
import ptyrun

    # Every name the table carries, plus the ones dropped from it -- those
    # must now resolve to the xterm fallback, and a row saying so is what
    # would catch one creeping back in.
_HOME = tempfile.mkdtemp(prefix="termcheck-home-")
# No -u NONE.  An empty $HOME, $VIM and $VIMRUNTIME are the isolation instead:
# slim-vim finds no ~/.vimrc, system vimrc or runtime defaults in them, and
# whim-vim, which has no -u from its Phase 18, looks for none of them anyway.
ENV = dict(os.environ, HOME=_HOME, VIM=os.path.join(_HOME, "novim"),
           VIMRUNTIME=os.path.join(_HOME, "novim"), XDG_CONFIG_HOME=os.path.join(_HOME, "xdg"))
for _k in ("VIMINIT", "EXINIT", "MYVIMRC"):
    ENV.pop(_k, None)

TERMS = ['xterm', 'xterm-256color', 'screen', 'screen-256color',
         'tmux', 'tmux-256color', 'alacritty-256color', 'vt100', 'ansi',
         'dumb', 'debug',
         'vt320', 'vt52', 'iris-ansi', 'pcansi', 'win32', 'amiga',
         'no-such-term-9x', '']

def ask(t, settle):
    d = tempfile.mkdtemp(prefix='termcheck-')
    open(os.path.join(d, 'f.txt'), 'w').write('one\ntwo\nthree\n')
    text, st = ptyrun.session(binary_path, ['f.txt'],
                              [b':set term? t_Co?\r', b':q!\r'],
                              term=t, cwd=d, settle=settle, env=ENV)
    s = text.decode('utf-8', 'replace')
        # The screen is full of '~' filler and the two answers land on
        # different screen lines; take each from its keyword onwards.
    got = []
    for x in s.splitlines():
        for kw in ('term=', 't_Co='):
            i = x.find(kw)
            if i >= 0:
                got.append(x[i:].split()[0])
    return got

def one(t):
        # An empty answer means the screen had not been drawn when the read
        # stopped, not that the terminal resolves to nothing -- and it happens
        # only under load, when verify.sh runs every harness at once.  Waiting
        # longer is the whole fix; a terminal that really answers nothing
        # answers nothing three times.
    for settle in (0.5, 1.5, 3.0):
        got = ask(t, settle)
        if got:
            break
    return 'TERM=%-20s -> %s' % (repr(t), ' '.join(got) or '(none)')


def main():
    global binary_path
    binary, out = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    binary_path = binary
    # One pty session per terminal, each mostly waiting; run them together and
    # reassemble in TERMS order so the output stays comparable.
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(TERMS)) as ex:
        rows = list(ex.map(one, TERMS))
    open(out, 'w').write('\n'.join(rows) + '\n')
    print('\n'.join(rows))

if __name__ == '__main__':
    main()
