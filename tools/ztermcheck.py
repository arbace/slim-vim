"""What each terminal name resolves to, asked with `+set term={name}`.

Usage: python3 tools/ztermcheck.py <binary> <outfile>

`tools/termcheck.py` is whim's and slim's, and zero phase 3 kept it as the fifth
part of a recording (ZERO-PLAN.md 2e) -- the one instrument the three pipelines
still share.  It opens a three-line file and asks the editor `:set term? t_Co?`
on a real pty, with the name it is asking about in `$TERM`:

    ptyrun.session(binary_path, ['f.txt'], [b':set term? t_Co?\r', b':q!\r'],
                   term=t, ...)

**Zero phase 5 removes the file argument from the command line**, so from that
boundary on `f.txt` is `Unknown option argument: "f.txt"`, the editor exits 1
before drawing anything, and all nineteen rows read `(none)`.  That is the
harness failing, not the terminal table moving -- and declaring `term-moved` for
it would switch the terminal table off for every phase after this one, which is
the one thing a phase must not buy its way out with.  Zero phase 5 therefore
asked the same question with an empty buffer, which needs no file.

**AND THE ANSWER WAS THE SAME NINETEEN TIMES, WHICH IS ZERO PHASE 33's REASON
FOR EXISTING.**  `$TERM` decides nothing here: whim phase 19 removed the
`getenv("TERM")` from `termcapinit()` -- "the terminal is what the build says" --
and left a compiled fallback of `"xterm-256color"`.  So every row of
`.reference/zero-baselines/ref-term.txt` read

    TERM='vt100'              -> term=xterm-256color t_Co=256

and the table was nineteen ways of recording that the environment does nothing.
MEASURED, and not argued: a prototype that DELETED eight of the ten built-in
terminal entries and three of the nine capability tables -- 118 lines -- passed
`tools/zcompare.py` against the real baselines declaring NOTHING AT ALL.  An
instrument that cannot see a phase is not an instrument.

So this asks with `+{command}`, which is the one facility ZERO-PLAN.md decision 8
promises to survive every phase, and reaches `did_set_term()` rather than
`termcapinit()`'s compiled default.  That is the only difference in WHAT IS ASKED
-- the other one, below, is that the scratch directory is now removed:
`tools/termcheck.py` is imported and two of its module globals --
`ask` and `one` -- are replaced, so the terminal list, the environment isolation,
the settle ladder's shape and the output format stay in one place and cannot
drift from whim's.  Editing termcheck.py itself is what ZERO-GOAL.md rule 9
forbids: it is named by tools/whimdelta.sh and tools/verify.sh, so its bytes are
in every whim stage's cache key.

Two things this has to get right, both measured:

  * **the error line echoes the assignment.**  A refused name draws
    `E522: Not found in termcap: term=vt320`, so a naive `find('term=')` reports
    the REQUESTED name as the result.  Any line carrying an `E<digits>:` code has
    the code taken off it and is then skipped, which is why a refusal records as
    `E522 term=xterm-256color t_Co=256` -- the error AND what the terminal
    actually stayed as.
  * **the row label is `:set term=` and not `TERM=`**, or the record would say
    `TERM='vt320'` about something that is not the environment at all.  That is
    why `one()` is overridden as well as `ask()`.

**Proven neutral before it was installed** (pipes/zero33.sh): `./zero-vim`
extracted from every recorded boundary tar, plus `whim-vim.c` built with whim's
own compile line, record the SAME nineteen rows -- one md5 across all of them.
The baseline and every phase's recording move together, so no phase's declared
delta changes and `term-moved` stays undeclared at every one of them.
"""
import os
import re
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import termcheck
import ptyrun

# `E522:`, `E529:` -- any Vim error code, not only the two this table draws, so a
# name that starts failing a NEW way is recorded rather than scraped for a `term=`
# that is the echoed request.
ERROR = re.compile(r'\bE\d+:')


def ask(t, settle):
    """termcheck.ask(), asking with `+set term={name}` instead of $TERM.

    No file argument and no file: zero phase 5 made a file argument an unknown
    option.  $TERM is left at ptyrun's default, since nothing in the editor has
    read it since whim phase 19 and pinning it keeps the pty itself constant.
    """
    d = tempfile.mkdtemp(prefix='ztermcheck-')
    try:
        text, _ = ptyrun.session(termcheck.binary_path, ['+set term=' + t],
                                 [b':set term? t_Co?\r', b':q!\r'],
                                 cwd=d, settle=settle, env=termcheck.ENV)
    finally:
        # AND IT IS REMOVED, which the tool this replaces did not do.  Every session
        # made a directory in /tmp and left it; measured, 182,319 of them were lying
        # there -- 100,280 termcheck-* and 82,039 ztermcheck-* -- and an ext4
        # directory that full answers `mkdir` with ENOSPC on a disk with 70 GB free.
        # That failed zero phase 9 in a run of this phase, a phase that has nothing
        # to do with terminals, which is the way this kind of leak is always found.
        shutil.rmtree(d, ignore_errors=True)
    s = text.decode('utf-8', 'replace')
    errs, got = [], []
    for x in s.splitlines():
        m = ERROR.search(x)
        if m:
            # The refusal, and NOT the `term=` it echoes back at us.
            code = m.group(0)[:-1]
            if code not in errs:
                errs.append(code)
            continue
        # The two answers land on different screen lines; take each from its
        # keyword onwards, exactly as termcheck.py does.
        for kw in ('term=', 't_Co='):
            i = x.find(kw)
            if i >= 0:
                got.append(x[i:].split()[0])
    return errs + got if got else []


def one(t):
    """termcheck.one(), with a label that says what was actually asked.

    The settle ladder is termcheck.one()'s and is here for the same reason: an
    empty answer means the screen had not been drawn when the read stopped, not
    that the name resolves to nothing, and it happens only under load.
    """
    for settle in (0.5, 1.5, 3.0):
        got = ask(t, settle)
        if got:
            break
    return ':set term=%-20s -> %s' % (repr(t), ' '.join(got) or '(none)')


if __name__ == '__main__':
    termcheck.ask = ask
    termcheck.one = one
    termcheck.main()
