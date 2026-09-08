"""A small fixed pty scenario, recorded so two binaries can be compared."""
import concurrent.futures
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ptyrun

ESC = b'\x1b'

SCENARIOS = [
    # name, TERM, argv, keystrokes
    ('edit_xterm', 'xterm', ['-u', 'NONE', '-i', 'NONE', 'f.txt'],
     [b'jjlx', b':set term?\r', b':set ts? sw? nu?\r', b':wq\r']),
    ('arrows', 'xterm', ['-u', 'NONE', '-i', 'NONE', 'f.txt'],
     [ESC + b'[B' + ESC + b'[B' + ESC + b'[C', b'x', b':wq\r']),
    ('unknown_term', 'no-such-term-9x', ['-u', 'NONE', '-i', 'NONE', 'f.txt'],
     [b'jjlx', b':set term?\r', b':wq\r']),
    ('insert_esc', 'xterm', ['-u', 'NONE', '-i', 'NONE', 'f.txt'],
     [b'ohello', ESC, b'0Diworld', ESC, b':wq\r']),
    ('screen_term', 'screen', ['-u', 'NONE', '-i', 'NONE', 'f.txt'],
     [b'GA!', ESC, b':set term?\r', b':wq\r']),
]

SEED = 'alpha one\nbeta two\ngamma three\ndelta four\n'


def one(scenario):
    name, term, argv, keys = scenario
    d = tempfile.mkdtemp(prefix='ptycheck-')
    open(os.path.join(d, 'f.txt'), 'w').write(SEED)
    text, status = ptyrun.session(binary_path, argv, keys, term=term,
                                  cwd=d, settle=0.6)
    body = open(os.path.join(d, 'f.txt'), 'rb').read()
    rows = ['=== %s (TERM=%s) status=%s\n--- file ---\n%s'
            % (name, term, status, body.decode('utf-8', 'replace'))]
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
