r"""Enumerators nothing mentions, deleted without moving the ones that stay.

Usage:
    python3 tools/deadenums.py <file> <enumvals.txt> [--delete]

**Nothing else in either pipeline looks at enumerators.** gcc has no warning for
one, `typereach.py` counts them only to decide whether their enum is alive, and
`deadsweep.py` never sees them.  So an enumerator whose option, command or
feature was removed ten phases ago is still sitting there.

Deleting one is not free, and this is the trap CLAUDE.md records: **an
enumerator's value is its position**, so removing one renumbers every implicit
one after it, and several enums in this file are the index of a parallel table.
The build is perfectly happy to re-point every later entry.

Of the dead ones here, 31 can go outright -- nothing follows them, or the next
survivor already has an explicit value -- and 49 would move a survivor.  Rather
than evaluate C expressions to work out what those values are (`1 << 3`,
`0x80000000L`, one enumerator defined in terms of another), the values are read
**from DWARF**, which is what `tools/enumvals.sh` dumps: the compiler has
already done the arithmetic.  The first survivor after each deleted run is
pinned to the value it had, and everything after it follows implicitly as
before.

The phase then dumps DWARF again and requires every surviving name to have the
same value it started with.  That is a stronger check than the build, which
would compile a silently renumbered table without complaint.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import cutil
import typereach as T


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    text = path.read_text(errors='surrogateescape')
    vals = {}
    for line in Path(sys.argv[2]).read_text().splitlines():
        if '=' in line:
            k, _, v = line.partition('=')
            vals[k.strip()] = v.strip()

    b = cutil.blank(text)
    defs = T.definitions(text, b)
    counts = {}
    for m in T.IDENT.finditer(b):
        counts[m.group()] = counts.get(m.group(), 0) + 1

    edits = []          # (start, end, replacement) over the whole file
    dead_total = pinned = stuck = 0
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
        pending = False         # a run of deletions is open before this entry
        for nm, raw in ent:
            if nm and counts.get(nm, 0) == 1:
                pending = True
                dead_total += 1
                continue
            if nm and pending and '=' not in raw and nm in vals:
                # pin it, so nothing after this point moves
                raw = re.sub(r'(\b%s\b)' % re.escape(nm), r'\1 = %s' % vals[nm],
                             raw, count=1)
                pinned += 1
            pending = False
            keep.append(raw)
        # split_top leaves a trailing empty fragment after the last comma, and
        # a run of deletions can leave fragments that are only whitespace.  An
        # enum rebuilt from those is `enum { }`, which is not C -- so count what
        # actually declares something before deciding there is anything left.
        if not any(T.IDENT.search(k) for k in keep):
            # EVERY CONSTANT IN THIS ENUM IS DEAD, and it still cannot go: an
            # empty enum is not C, and the enum's own type is in use.  One of
            # these is left in the file -- `omacc_T`, whose three constants are
            # dead because every field of `ocmember_T` is dead, and
            # deadfields.py will not empty a struct out.  It is a type-level
            # island one level below what typereach.py models: the type is
            # reachable through a field nothing reads.
            #
            # Counted apart, because the phase has to be able to tell "you did
            # not finish" from "this cannot be expressed".
            stuck += sum(1 for nm, _ in ent if nm and counts.get(nm, 0) == 1)
            dead_total -= sum(1 for nm, _ in ent if nm and counts.get(nm, 0) == 1)
            continue
        edits.append((a + o + 1, a + c, ','.join(keep)))

    if '--delete' in sys.argv:
        for s0, e0, rep in sorted(edits, reverse=True):
            text = text[:s0] + rep + text[e0:]
        path.write_text(text, errors='surrogateescape')
    print('  deadenums    %d enumerators nothing mentions, %d survivors pinned%s'
          % (dead_total, pinned,
             '; %d in enums where every constant is dead and the type is in '
             'use, which cannot be expressed' % stuck if stuck else ''))
    return dead_total


if __name__ == '__main__':
    sys.exit(0 if main() == 0 else 1)
