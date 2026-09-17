"""What each TERM resolves to, asked without a file argument.

Usage: python3 tools/ztermcheck.py <binary> <outfile>

`tools/termcheck.py` is whim's and slim's, and zero phase 3 kept it as the fifth
part of a recording (ZERO-PLAN.md 2e) -- the one instrument the three pipelines
still share.  It opens a three-line file and asks the editor `:set term? t_Co?`
on a real pty, and the file is how the screen gets something on it:

    ptyrun.session(binary_path, ['f.txt'], [b':set term? t_Co?\r', b':q!\r'], ...)

**Zero phase 5 removes the file argument from the command line**, so from that
boundary on `f.txt` is `Unknown option argument: "f.txt"`, the editor exits 1
before drawing anything, and all nineteen rows read `(none)`.  That is the
harness failing, not the terminal table moving -- and declaring `term-moved` for
it would switch the terminal table off for every phase after this one, which is
the one thing a phase must not buy its way out with.

So zero asks the same question with an empty buffer, which needs no file.  This
is that one difference and nothing else: `tools/termcheck.py` is imported and its
`ask()` replaced, so the terminal list, the environment isolation, the settle
ladder and the output format stay in one place and cannot drift from whim's.
Editing termcheck.py itself is what ZERO-GOAL.md rule 9 forbids -- it is named by
tools/whimdelta.sh and tools/verify.sh, so its bytes are in every whim stage's
cache key.

**Proven neutral before it was installed**: recorded from the binary zero phase 5
was handed -- which still accepts a file argument, so both forms work on it --
this produces `.reference/zero-baselines/ref-term.txt` byte for byte, all
nineteen rows.  The instrument changed and the recording did not.
"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import termcheck
import ptyrun


def ask(t, settle):
    """termcheck.ask(), with no file argument and no file."""
    d = tempfile.mkdtemp(prefix='ztermcheck-')
    text, _ = ptyrun.session(termcheck.binary_path, [],
                             [b':set term? t_Co?\r', b':q!\r'],
                             term=t, cwd=d, settle=settle, env=termcheck.ENV)
    s = text.decode('utf-8', 'replace')
    # The two answers land on different screen lines; take each from its keyword
    # onwards, exactly as termcheck.py does.
    got = []
    for x in s.splitlines():
        for kw in ('term=', 't_Co='):
            i = x.find(kw)
            if i >= 0:
                got.append(x[i:].split()[0])
    return got


if __name__ == '__main__':
    termcheck.ask = ask
    termcheck.main()
