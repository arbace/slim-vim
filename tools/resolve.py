"""Resolve conditional groups from per-translation-unit marker votes.

Every unit that reaches a group votes.  A group is resolved only if all voters
agree; otherwise it is left exactly as it was, which is the right answer for
the handful of groups whose answer genuinely differs between units.

Usage: resolve.py [--no-guards] <live-dir> <file> ...
"""
import os
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cond
from plant import marker

STATS = {'one': 0, 'none': 0, 'disagree': 0, 'unreached': 0, 'guard': 0}


def vote(base, nbranch, counts):
    """None if not reached; -1 if reached and never taken; index; 'conflict'.

    Counts, not presence.  A header can be read twice in one translation unit
    -- ex_cmds.h is, with DO_DECLARE_EXCMD toggled between the two -- and then
    a branch taken on the first pass and skipped on the second looks live if
    you only ask whether its marker appeared.  Removing that #ifndef makes the
    second pass emit the whole enum a second time.  A branch is uniformly live
    only when its marker appears exactly as often as the group was reached.
    """
    ctx = counts.get(marker(base), 0)
    if ctx == 0:
        return None
    got = [counts.get(marker(base + 1 + bi), 0) for bi in range(nbranch)]
    if sum(got) == 0:
        return -1
    hits = [bi for bi, c in enumerate(got) if c]
    if len(hits) == 1 and got[hits[0]] == ctx:
        return hits[0]
    return 'conflict'


def decide(base, nbranch, tallies):
    votes = {vote(base, nbranch, t) for t in tallies}
    votes.discard(None)
    if not votes:
        return 'unreached'
    if len(votes) > 1 or 'conflict' in votes:
        return 'disagree'
    return votes.pop()


def emit(nodes, lines, out, ids, tallies):
    for n in nodes:
        if isinstance(n, int):
            out.append(lines[n])
            continue
        g = n
        base, guard = ids[id(g)]
        if guard:
            STATS['guard'] += 1
            keep = True
        else:
            d = decide(base, len(g.branches), tallies)
            if d == 'unreached':
                STATS['unreached'] += 1
                continue
            if d == 'disagree':
                STATS['disagree'] += 1
                keep = True
            elif d == -1:
                STATS['none'] += 1
                continue
            else:
                STATS['one'] += 1
                emit(g.branches[d][1], lines, out, ids, tallies)
                continue
        for bi, (dline, body) in enumerate(g.branches):
            out.append(lines[dline])
            emit(body, lines, out, ids, tallies)
        out.append(lines[g.end_line])


def main():
    args = list(sys.argv[1:])

    # Once the tree is one translation unit, nothing can be included twice, so
    # the include-guard exception has nothing left to protect -- and every
    # guard is then a group whose answer is finally knowable.  Phase 6 passes
    # this; Phase 5 must not.
    no_guards = '--no-guards' in args
    if no_guards:
        args.remove('--no-guards')
    sys.argv = [sys.argv[0]] + args

    livedir = sys.argv[1]
    tallies = []
    for f in sorted(os.listdir(livedir)):
        d = {}
        for line in open(os.path.join(livedir, f)):
            c, m = line.split()
            d[m] = int(c)
        tallies.append(d)
    print('%d translation units voting' % len(tallies))
    n = removed = 0
    for path in sorted(sys.argv[2:]):
        lines = open(path, encoding='utf-8', errors='surrogateescape').read().split('\n')
        nodes, _ = cond.parse(lines)
        ids = {}
        for g in cond.walk(nodes):
            ids[id(g)] = (n + 1, False if no_guards
                          else cond.is_include_guard(g, lines))
            n += 1 + len(g.branches)
        out = []
        emit(nodes, lines, out, ids, tallies)
        removed += len(lines) - len(out)
        text = '\n'.join(out)
        if not text.endswith('\n'):
            text += '\n'
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write(text)
    print('resolved to one branch: %(one)d, dropped (no branch live): %(none)d, '
          'never reached: %(unreached)d, left alone (units disagree): %(disagree)d, '
          'include guards: %(guard)d' % STATS)
    print('%d lines removed' % removed)


if __name__ == '__main__':
    main()
