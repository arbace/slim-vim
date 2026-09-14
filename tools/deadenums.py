r"""Enumerators nothing mentions, deleted without moving the ones that stay.

Usage:
    python3 tools/deadenums.py <file> <enumvals.txt>             report
    python3 tools/deadenums.py <file> <enumvals.txt> --delete    delete
    python3 tools/deadenums.py <file> <enumvals.txt> --verify    check after

**Nothing else in either pipeline looks at enumerators.** gcc has no warning for
one, `typereach.py` counts them only to decide whether their enum is alive, and
`deadsweep.py` never sees them.  So an enumerator whose option, command or
feature was removed ten phases ago is still sitting there.

Deleting one is not free, and this is the trap CLAUDE.md records: **an
enumerator's value is its position**, so removing one renumbers every implicit
one after it, and several enums in this file are the index of a parallel table.
The build is perfectly happy to re-point every later entry.

Rather than evaluate C expressions to work out what the values are (`1 << 3`,
`0x80000000L`, one enumerator defined in terms of another), they are read **from
DWARF**, which is what `tools/enumvals.sh` dumps: the compiler has already done
the arithmetic.  The first survivor after each deleted run is pinned to the
value it had, and everything after it follows implicitly as before.

THE VALUES ARE DUMPED ON FIRST NEED.  `--delete` with no values file yet asks
whether anything is dead, and only then compiles with `-g` and writes the file.
That is what lets every sweep round in every phase ask the question for about a
second: most rounds find nothing, and a dump costs a full debug build.  A dump
taken later in a sweep is still the ORIGINAL numbering, because nothing before
the first deletion can have moved an enumerator -- and the caller keeps the same
file for the whole sweep, so later rounds pin to the same values.

A SURVIVOR DWARF HAS NO VALUE FOR CANNOT BE PINNED, and the run before it stays.
gcc does not emit every enum, and an unpinned survivor is silently renumbered --
which the before-and-after comparison cannot see either, because the name is in
neither dump.  Keeping the run is the only answer that is known to be right.

`--verify` dumps DWARF again and requires every name present in both dumps to
have the value it started with.  That is a stronger check than the build, which
compiles a silently renumbered table without complaint.
"""

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil
import typereach as T

HERE = __file__.rsplit('/', 1)[0]


def load(path):
    vals = {}
    if os.path.exists(path):
        for line in Path(path).read_text().splitlines():
            if '=' in line:
                k, _, v = line.partition('=')
                vals[k.strip()] = v.strip()
    return vals


def dump(src, out):
    subprocess.run(['sh', os.path.join(HERE, 'enumvals.sh'), src, out], check=True)


def analyse(text, vals):
    """(edits, deletable, pinned, stuck, unpinnable) for this text and these values."""
    b = cutil.blank(text)
    defs = T.definitions(text, b)
    counts = {}
    for m in T.IDENT.finditer(b):
        counts[m.group()] = counts.get(m.group(), 0) + 1

    edits = []          # (start, end, replacement) over the whole file
    dead_total = pinned = stuck = unpinnable = 0
    for a, z, _, _ in defs:
        body = text[a:z]
        if not re.match(r'^\s*(typedef\s+)?enum\b', body):
            continue
        o = body.find('{')
        c = body.rfind('}')
        if o < 0 or c < 0:
            continue
        inner = body[o + 1:c]
        parts = cutil.split_top(inner, ',', cutil.blank(inner))
        ent = []
        for p in parts:
            m = T.IDENT.search(p)
            ent.append((m.group() if m else None, p))
        if not any(nm and counts.get(nm, 0) == 1 for nm, _ in ent):
            continue
        keep = []
        run = []                # the dead entries deleted since the last survivor
        deleted = kept_back = 0
        for nm, raw in ent:
            if nm and counts.get(nm, 0) == 1:
                run.append(raw)
                continue
            if nm and run and '=' not in raw:
                if nm not in vals:
                    kept_back += len(run)
                    keep.extend(run)
                    run = []
                    keep.append(raw)
                    continue
                # pin it, so nothing after this point moves
                raw = re.sub(r'(\b%s\b)' % re.escape(nm), r'\1 = %s' % vals[nm],
                             raw, count=1)
                pinned += 1
            deleted += len(run)
            run = []
            keep.append(raw)
        deleted += len(run)
        # split_top leaves a trailing empty fragment after the last comma, and
        # a run of deletions can leave fragments that are only whitespace.  An
        # enum rebuilt from those is `enum { }`, which is not C -- so count what
        # actually declares something before deciding there is anything left.
        if not any(T.IDENT.search(k) for k in keep):
            # EVERY CONSTANT IN THIS ENUM IS DEAD, and it still cannot go: an
            # empty enum is not C, and the enum's own type is in use.  One of
            # these is left in whim-vim.c -- `omacc_T`, whose three constants
            # are dead because every field of `ocmember_T` is dead, and
            # deadfields.py will not empty a struct out.  It is a type-level
            # island one level below what typereach.py models: the type is
            # reachable through a field nothing reads.
            #
            # Counted apart, because a sweep has to be able to tell "you did
            # not finish" from "this cannot be expressed".
            stuck += deleted + kept_back
            continue
        dead_total += deleted
        unpinnable += kept_back
        if deleted:
            edits.append((a + o + 1, a + c, ','.join(keep)))
    return edits, dead_total, pinned, stuck, unpinnable


def verify(src, before):
    fd, after = tempfile.mkstemp()
    os.close(fd)
    try:
        dump(src, after)
        b, a = load(before), load(after)
    finally:
        os.unlink(after)
    moved = sorted(k for k in b if k in a and a[k] != b[k])
    gone = sum(1 for k in b if k not in a)
    if moved:
        print('  enumvals     %d surviving enumerators changed value: %s'
              % (len(moved), ' '.join(moved[:8])))
        return 1
    print('  enumvals     %d enumerators gone, and not one survivor moved' % gone)
    return 0


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    valpath = sys.argv[2]
    if '--verify' in sys.argv:
        return verify(str(path), valpath)
    text = path.read_text(errors='surrogateescape')

    vals = load(valpath)
    edits, dead_total, pinned, stuck, unpinnable = analyse(text, vals)
    if '--delete' in sys.argv and not os.path.exists(valpath) and (dead_total or unpinnable):
        # First need: the values of THIS text, before anything is deleted.
        dump(str(path), valpath)
        vals = load(valpath)
        edits, dead_total, pinned, stuck, unpinnable = analyse(text, vals)

    if '--delete' in sys.argv and edits:
        for s0, e0, rep in sorted(edits, reverse=True):
            text = text[:s0] + rep + text[e0:]
        path.write_text(text, errors='surrogateescape')
    print('  deadenums    %d enumerators nothing mentions, %d survivors pinned%s%s'
          % (dead_total, pinned,
             '; %d in enums where every constant is dead and the type is in '
             'use, which cannot be expressed' % stuck if stuck else '',
             '; %d kept before a survivor DWARF has no value for' % unpinnable
             if unpinnable else ''))
    return dead_total


if __name__ == '__main__':
    sys.exit(0 if main() == 0 else 1)
