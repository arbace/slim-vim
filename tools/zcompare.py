"""Compare a zero recording with the baselines, against what was declared.

Usage: python3 tools/zcompare.py <baseline-dir> <new-dir> <delta-file> <phase>
       python3 tools/zcompare.py --declared <delta-file> <phase>

`tools/zerodelta.sh` makes the recording and calls this; the rule is
`tools/whimdelta.sh`'s -- **exactly** what the phase declared moved, and nothing
else.  A declaration that is merely widened to fit is not a check, and a
declaration that names something which did not move is also a failure.

THE GRAMMAR, which `pipes/zero.delta` states and this reads:

    word            an Ex command name: its block in ref-excmds.txt may differ
    case:NAME       a screen case (tools/zcases.py) whose record may differ
    argv:NAME       an invocation (tools/zargv.py); spaces are written as `_`
    term-moved      the terminal table (tools/termcheck.py) differs
    pty-moved       the pty scenarios (tools/zpty.py) differ
    screen-moved    what the editor DRAWS differs everywhere: the snapshots and
                    the stream digest in every case, the text and message lines
                    in every command row.  Exit status, bells and stderr must
                    still match
    stderr-moved    what the editor writes to STDERR differs everywhere, and
                    nothing else does
    drop:X          X was declared by an earlier phase and no longer differs

The two `-moved` dimensions are not a way of saying "some things changed": each
excludes ONE dimension from every comparison and requires that dimension to have
actually moved somewhere.  Anything outside it is still checked case by case.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zrec


def declared(path, phase):
    """Every token up to `phase`, and the ones `phase` itself declares."""
    tokens, own, cur = set(), [], None
    for line in open(path):
        line = line.split('#')[0]
        if not line.strip():
            continue
        words = line.split()
        if words and words[0].isdigit() and not line[:1].isspace():
            cur = int(words[0])
            words = words[1:]
        if cur is None or cur > phase:
            continue
        for w in words:
            if w.startswith('drop:'):
                tokens.discard(w[5:])
            else:
                tokens.add(w)
            if cur == phase:
                own.append(w)
    return tokens, own


def dimensions(tokens):
    d = set()
    if 'screen-moved' in tokens:
        d.add('screen')
    if 'stderr-moved' in tokens:
        d.add('stderr')
    return d


def compare_set(base, new, prefix, tokens, dims, moved_dim):
    """Per-record comparison.  Returns (unexplained, declared-but-static)."""
    bad, still = [], []
    names = sorted(set(base) | set(new))
    for n in names:
        b, x = base.get(n), new.get(n)
        token = n if prefix == '' else prefix + n.replace(' ', '_')
        if b == x:
            if token in tokens:
                still.append(token)
            continue
        if token in tokens:
            continue
        if dims and zrec.without(b or '', dims) == zrec.without(x or '', dims):
            # WHICH dimension moved is asked of each one alone: with two tokens
            # declared, "the difference vanishes under both" would otherwise let
            # a token nothing touched pass as used.
            for d in dims:
                if zrec.only(b or '', d) != zrec.only(x or '', d):
                    moved_dim.add(d)
            continue
        bad.append(token)
    return bad, still


def read_blocks(path):
    if not os.path.exists(path):
        return {}
    return zrec.blocks(open(path, errors='replace').read())


def read_dir(path):
    if not os.path.isdir(path):
        return {}
    return {n: open(os.path.join(path, n), errors='replace').read()
            for n in os.listdir(path)}


def main():
    if sys.argv[1] == '--declared':
        _, own = declared(sys.argv[2], int(sys.argv[3]))
        print('\n'.join(own))
        return 0

    basedir, newdir, delta, phase = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
    tokens, _ = declared(delta, phase)
    dims = dimensions(tokens)
    moved_dim = set()
    fail, report = [], []

    for what, kind, prefix in (('screen', 'dir', 'case:'),
                               ('ref-excmds.txt', 'blocks', ''),
                               ('ref-argv.txt', 'blocks', 'argv:')):
        path_b, path_n = os.path.join(basedir, what), os.path.join(newdir, what)
        if kind == 'dir':
            b, x = read_dir(path_b), read_dir(path_n)
        else:
            b, x = read_blocks(path_b), read_blocks(path_n)
        if not b:
            fail.append('  delta        the baselines hold no %s -- zero phase 0 records it' % what)
            continue
        bad, still = compare_set(b, x, prefix, tokens, dims, moved_dim)
        if bad:
            fail.append('  delta        %s moved and was not declared: %s' % (what, ' '.join(bad)))
        if still:
            fail.append('  delta        %s was declared for %s and did not move: %s'
                        % ('a token' if len(still) > 1 else 'a token', what, ' '.join(still)))
        report.append('%s %d/%d' % (what, len(b) - len(bad) - len(still), len(b)))

    for what, token in (('ref-term.txt', 'term-moved'), ('ref-pty.txt', 'pty-moved')):
        pb, pn = os.path.join(basedir, what), os.path.join(newdir, what)
        same = (os.path.exists(pb) and os.path.exists(pn)
                and open(pb, errors='replace').read() == open(pn, errors='replace').read())
        if token in tokens and same:
            fail.append('  delta        %s was declared to move and did not' % token)
        if token not in tokens and not same:
            fail.append('  delta        %s moved, and no %s is declared' % (what, token))

    for d, token in (('screen', 'screen-moved'), ('stderr', 'stderr-moved')):
        if d in dims and d not in moved_dim:
            fail.append('  delta        %s was declared and nothing moved in that dimension'
                        % token)

    if fail:
        print('\n'.join(fail))
        print('               A phase here may change behaviour, but only the behaviour')
        print('               it said it would.  Anything else is a bug, and a delta')
        print('               list that is merely widened to fit is not a check.')
        return 1

    shown = sorted(t for t in tokens)
    print('  delta        exactly as declared: %s' % (' '.join(shown) if shown else 'none'))
    print('               %s' % ', '.join(report))
    return 0


if __name__ == '__main__':
    sys.exit(main())
