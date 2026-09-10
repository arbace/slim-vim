#!/usr/bin/env python3
"""Delete the #define directives nothing mentions.  Exactly one round.

Usage:
    python3 tools/dropmacros.py <file>

A quarter of the macros in this tree are named nowhere but their own
definition, and deleting them first is worth more than it sounds: every one
removed is one that does not have to be converted to an enumerator, expanded at
its use sites, or reasoned about at all.

**One round, and this is not a matter of taste.**  Iterating to a fixpoint
finds more -- 910, then 46, then 2 -- and those 48 really are dead.  It also
produces a different vim.c, permanently, because the number of rounds decides
how many constants ever reach toenum.py: 1,444 enumerators against 1,410.  The
evidence that one round is the settled answer is in the reference tree, where
`VIM_VERSION_BUILD` survives as an enumerator.  Round 1 removes
VIM_VERSION_BUILD_STR, which is what referenced it; a second round would remove
VIM_VERSION_BUILD too, and toenum.py would never see it.

So: count once, delete once, stop.  A tool that helpfully iterated would be
wrong in a way that compiles, runs, and passes every behavioural check.
"""

import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, __file__.rsplit('/', 1)[0])
import macros

WORD = re.compile(r'[A-Za-z_]\w*')


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    lines = path.read_text(errors='surrogateescape').split('\n')

    defined = {}
    for lineno, name, params, body in macros.parse(str(path)):
        defined.setdefault(name, []).append(lineno - 1)

    # Every mention that is not a definition of the name itself.
    seen = Counter()
    for i, line in enumerate(lines):
        m = macros.DEFINE.match(line)
        words = WORD.findall(line)
        if m:
            # Skip the macro's own name once; its body still counts, because a
            # live macro's body is a real reference to what it names.
            words.remove(m.group(1))
        seen.update(words)

    drop = {i for name, at in defined.items() if seen[name] == 0 for i in at}

    out = [l for i, l in enumerate(lines) if i not in drop]
    path.write_text('\n'.join(out), errors='surrogateescape')
    print('  dropmacros   %d of %d defines mentioned nowhere else, one round'
          % (len(drop), sum(len(v) for v in defined.values())))


if __name__ == '__main__':
    main()
