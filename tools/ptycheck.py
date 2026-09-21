"""A small fixed pty scenario, recorded so two binaries can be compared.

**A MODIFIED KEY IS A DIFFERENT KEY, and nothing here pressed one for forty
phases.**  `arrows` presses the plain arrows, and so did the zero pipeline's `zcases.py`
(`ins_arrows`, `nav_arrows`) and `zpty.py` (`nav_arrows`), now in
github.com/arbace/go-whim; every other `\\x1b` in every harness of all three
pipelines was a bare Escape.  A shifted
arrow takes a different path entirely -- `ins_start_select()` in Insert mode
and the `NV_SS`/`NV_SSS` arms of `normal_cmd()` in Normal mode, all three
gated on `km_startsel` -- so a default that only those three read could be
wrong in every build ever made and every recording agree.  It was:
`keymodel=startsel` is one of Phase 1's eighteen compiled-in defaults, and
`set_options_default()` installs a VALUE without running the callback that
computes the flag, so `:set km?` said `startsel` while `km_startsel` stayed
FALSE.  `shift_arrows` is the case that would have seen it, and `--- mode ---`
is what it records.
"""
import atexit
import concurrent.futures
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ptyrun

ESC = b'\x1b'

SCENARIOS = [
    # name, TERM, argv, keystrokes
    ('edit_xterm', 'xterm', ['f.txt'],
     [b'jjlx', b':set term?\r', b':set ts? sw? nu?\r', b':wq\r']),
    ('arrows', 'xterm', ['f.txt'],
     [ESC + b'[B' + ESC + b'[B' + ESC + b'[C', b'x', b':wq\r']),
    # 'keymodel' is startsel here, so a SHIFTED arrow in Normal mode starts a
    # selection instead of moving a word: two of them select `alp` and `x`
    # leaves `ha one`.  Without the flag they are two `w` motions onto line 2
    # and `x` leaves `eta two` on it -- which is what every build of this
    # editor did until the flag was initialised by hand.  The file is the
    # evidence and `--- mode ---` is the reading: both move, together.
    ('shift_arrows', 'xterm', ['f.txt'],
     [ESC + b'[1;2C' + ESC + b'[1;2C', b'x', b':wq\r']),
    ('unknown_term', 'no-such-term-9x', ['f.txt'],
     [b'jjlx', b':set term?\r', b':wq\r']),
    ('insert_esc', 'xterm', ['f.txt'],
     [b'ohello', ESC, b'0Diworld', ESC, b':wq\r']),
    ('screen_term', 'screen', ['f.txt'],
     [b'GA!', ESC, b':set term?\r', b':wq\r']),
]

# Every mode the editor announces on the message line.  Which of them a scenario
# entered is a fact about the editor and not about the machine, so it is recorded
# per scenario; the screen dump it is read out of is not, and is not.
MODES = ('VISUAL', 'SELECT', 'INSERT', 'REPLACE')

_HOME = tempfile.mkdtemp(prefix="ptycheck-home-")
# Removed on the way out.  tools/termcheck.py leaked one of these per pty session
# until 17f7f44, and 182,319 of them made `mkdir` answer ENOSPC on a disk with
# 70 GB free -- a directory is an inode and a directory entry, and neither is disk.
atexit.register(shutil.rmtree, _HOME, True)
# No -u NONE.  An empty $HOME, $VIM and $VIMRUNTIME are the isolation instead:
# slim-vim finds no ~/.vimrc, system vimrc or runtime defaults in them, and
# whim-vim, which has no -u from its Phase 18, looks for none of them anyway.
ENV = dict(os.environ, HOME=_HOME, VIM=os.path.join(_HOME, "novim"),
           VIMRUNTIME=os.path.join(_HOME, "novim"), XDG_CONFIG_HOME=os.path.join(_HOME, "xdg"))
for _k in ("VIMINIT", "EXINIT", "MYVIMRC"):
    ENV.pop(_k, None)

SEED = 'alpha one\nbeta two\ngamma three\ndelta four\n'


def one(scenario):
    name, term, argv, keys = scenario
    d = tempfile.mkdtemp(prefix='ptycheck-')
    try:
        open(os.path.join(d, 'f.txt'), 'w').write(SEED)
        text, status = ptyrun.session(binary_path, argv, keys, term=term,
                                      cwd=d, settle=0.6, env=ENV)
        body = open(os.path.join(d, 'f.txt'), 'rb').read()
    finally:
        shutil.rmtree(d, ignore_errors=True)
    screen = text.decode('utf-8', 'replace')
    # Which modes the editor announced, over the whole session and not the final
    # screen: the keys that quit wipe the message line, so `-- VISUAL --` lives
    # in the bytes before them and nowhere else.
    modes = [m for m in MODES if '-- %s --' % m in screen]
    rows = ['=== %s (TERM=%s) status=%s\n--- file ---\n%s'
            % (name, term, status, body.decode('utf-8', 'replace')),
            '--- mode --- ' + (' '.join(modes) or 'none')]
    return text, rows


def main():
    global binary_path
    binary, out = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    binary_path = binary
    # Each scenario is an independent pty session spending most of its time
    # waiting for keystroke delays, so they run together.  Results are
    # reassembled in scenario order: the output has to be comparable, not
    # whatever finished first.
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(SCENARIOS)) as ex:
        results = list(ex.map(one, SCENARIOS))
    rows = []
    for (text, head) in results:
        rows.extend(head)
        # The screen dump itself is too timing-dependent to compare directly;
        # what is recorded is the lines that answer a :set query, which are not.
        seen = set()
        for line in text.decode('utf-8', 'replace').splitlines():
            s = line.strip()
            if not s:
                continue
            for key in ('term=', 'tabstop=', 'shiftwidth=', 'number'):
                if key in s and s not in seen:
                    seen.add(s)
                    rows.append('--- report --- ' + s)
                    break
    open(out, 'w').write('\n'.join(rows) + '\n')
    print(len(SCENARIOS), 'pty scenarios ->', out)


if __name__ == '__main__':
    main()
