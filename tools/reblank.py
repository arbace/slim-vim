"""Restore the blank-line paragraphing the comment-removal pass lost.

Line numbers are useless here: everything since has joined, split, braced,
deleted and merged lines.  The anchor is *content*.  In the tree as it stood
before comments were removed, every blank line sits between two identifiable
lines; find that pair adjacent in vim.c and put the blank line back.

Normalisation has to make the two comparable: strip comments from the old text
(one space, as translation phase 3 says), then collapse whitespace on both
sides.  Lines that Phase 7 joined or split will not match and are simply not
recovered.

Usage: reblank.py <old-tree-dir> <vim.c>
"""
import glob
import os
import re
import sys

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil


def norm(line):
    s = cutil.strip_comments_only(line)
    s = re.sub(r'\s+', ' ', s).strip()
    return s


def pairs_from(old_dir):
    """(separated, together) counts for every adjacent line pair.

    Presence is not enough -- that mistake again.  `}` followed by `}` occurs
    with a blank between it somewhere in 160,000 lines, and inserting one at
    every occurrence doubles the blank-line count.  What matters is whether the
    pair is *usually* separated: count both ways and let the majority decide.
    """
    sep, tog = {}, {}
    files = sorted(glob.glob(os.path.join(old_dir, '*.c')) +
                   glob.glob(os.path.join(old_dir, '*.h')) +
                   glob.glob(os.path.join(old_dir, 'proto', '*.pro')))
    for p in files:
        lines = open(p, encoding='utf-8', errors='surrogateescape').read().split('\n')
        # A line that normalises to nothing is either a blank line or a
        # comment-only line, and they are not the same thing.  Counting a
        # comment as a gap puts a blank line wherever a comment used to be --
        # 3,442 of them immediately after an opening brace, which is not this
        # tree's style and was not the old tree's either.  A comment is
        # skipped; only a truly blank line is a gap.
        prev = None
        gap = False
        for raw in lines:
            n = norm(raw)
            if not n:
                if not raw.strip():
                    if prev is not None:
                        gap = True
                continue
            if prev is not None:
                d = sep if gap else tog
                d[(prev, n)] = d.get((prev, n), 0) + 1
            prev = n
            gap = False
    return sep, tog, len(files)


def anchors_from(old_dir):
    """Lines that are *usually* followed by a blank line.

    A weaker rule than the pair, for the 29% of blank lines with only one
    surviving neighbour.  It is safe only because of the majority test: a
    closing brace is followed by a blank often enough to notice and not often
    enough to win, so it never fires.  What does fire is almost all the
    declaration-block rule -- `int l;` before the first statement.

    Two placements are refused outright: after a line ending in `{`, and
    before a closing brace.  Both are wrong wherever they appear, and the
    second would have accounted for more than half the hits.
    """
    after_blank, after_code = {}, {}
    files = sorted(glob.glob(os.path.join(old_dir, '*.c')) +
                   glob.glob(os.path.join(old_dir, '*.h')) +
                   glob.glob(os.path.join(old_dir, 'proto', '*.pro')))
    for p in files:
        prev = None
        for raw in open(p, encoding='utf-8', errors='surrogateescape'):
            n = norm(raw)
            if not n:
                if not raw.strip() and prev is not None:
                    after_blank[prev] = after_blank.get(prev, 0) + 1
                    prev = None
                continue
            if prev is not None:
                after_code[prev] = after_code.get(prev, 0) + 1
            prev = n
    return {k for k, v in after_blank.items() if v > after_code.get(k, 0)}


def main():
    old_dir, target = sys.argv[1], sys.argv[2]
    sep, tog, nfiles = pairs_from(old_dir)
    want = {k for k, v in sep.items() if v > tog.get(k, 0)}
    print('%d files, %d pairs seen separated, %d of them usually so'
          % (nfiles, len(sep), len(want)))

    lines = open(target, encoding='utf-8', errors='surrogateescape').read().split('\n')
    norms = [norm(l) for l in lines]
    # Bracing inserted lines between pairs that used to be adjacent: a blank
    # after a one-line `if` body now has the body's closing brace in the way.
    # Step over lines that are nothing but a brace when looking for the pair,
    # and put the blank immediately before the second half of it.
    brace_only = [n in ('{', '}') for n in norms]
    insert_before = set()
    added = 0
    for i, n in enumerate(norms):
        if not n or brace_only[i]:
            continue
        j = i + 1
        while j < len(lines) and (brace_only[j] or not norms[j]):
            if not norms[j]:
                break                     # already separated
            j += 1
        if j >= len(lines) or not norms[j]:
            continue
        if (n, norms[j]) in want:
            insert_before.add(j)
            added += 1
    out = []
    for i, line in enumerate(lines):
        if i in insert_before:
            out.append('')
        out.append(line)
    # a blank immediately after an opening brace is not this file's style
    cleaned, dropped = [], 0
    for line in out:
        if line == '' and cleaned and cleaned[-1].rstrip().endswith('{'):
            dropped += 1
            continue
        cleaned.append(line)
    if '--anchors' in sys.argv:
        usually = anchors_from(old_dir)
        norms2 = [norm(l) for l in cleaned]
        again, extra = [], 0
        for i, line in enumerate(cleaned):
            again.append(line)
            n = norms2[i]
            if not n or i + 1 >= len(cleaned) or not norms2[i + 1]:
                continue
            if n in usually and not n.endswith('{') and norms2[i + 1] != '}':
                again.append('')
                extra += 1
        cleaned = again
        print('%d further blanks from single-line anchors' % extra)

    text = '\n'.join(cleaned)
    if not text.endswith('\n'):
        text += '\n'
    open(target, 'w', encoding='utf-8', errors='surrogateescape').write(text)
    print('%d blank lines restored (%d dropped again after an opening brace)'
          % (added - dropped, dropped))


if __name__ == '__main__':
    main()
