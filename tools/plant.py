"""Plant markers in every conditional group: one per branch, plus one just
before the group itself.

The extra marker is what makes the measurement sound.  Without it a group that
is reached in one translation unit and not in another looks like "exactly one
branch is live" -- and resolving it to that branch changes every other
translation unit.  That is exactly what happens to #ifdef DO_INIT in globals.h,
which only main.c ever takes: resolving it gave all 66 other units the
initialisers that belong to main.c alone.

With a context marker, each translation unit votes: not reached, no branch
live, branch N live, or conflict.  A group is only resolved when every unit
that reaches it agrees.

Marker ids come from a deterministic walk over the sorted file list, so the
resolve pass recomputes them from the pristine sources with no state carried.

Usage: plant.py <file> ...
"""
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cond

PREFIX = 'ZMK'


def marker(n):
    return '%s_%d_%s' % (PREFIX, n, PREFIX)


def assign(path, lines):
    """[(group, base_id, is_guard)] in the deterministic walk order."""
    nodes, _ = cond.parse(lines)
    return nodes, list(cond.walk(nodes))


def main():
    n = 0
    groups = guards = 0
    for path in sorted(sys.argv[1:]):
        lines = open(path, encoding='utf-8', errors='surrogateescape').read().split('\n')
        nodes, gs = assign(path, lines)
        before = {}     # line index -> markers to put BEFORE that line
        after = {}      # line index -> markers to put AFTER that line
        for g in gs:
            base = n + 1
            n += 1 + len(g.branches)
            groups += 1
            if cond.is_include_guard(g, lines):
                guards += 1
                continue
            before.setdefault(g.open_line, []).append(marker(base))
            for bi, (dline, _) in enumerate(g.branches):
                after.setdefault(dline, []).append(marker(base + 1 + bi))
        if not before and not after:
            continue
        out = []
        for i, ln in enumerate(lines):
            if i in before:
                out.extend(before[i])
            out.append(ln)
            if i in after:
                out.extend(after[i])
        open(path, 'w', encoding='utf-8', errors='surrogateescape').write('\n'.join(out))
    print('%d groups (%d include guards left unmarked), %d marker ids' % (groups, guards, n))


if __name__ == '__main__':
    main()
