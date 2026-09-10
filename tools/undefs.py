#!/usr/bin/env python3
"""Remove #undef, renaming the macros that were relying on it.

Usage:
    python3 tools/undefs.py <renames.txt> <keep-macro,...> <file> ...

#undef exists so a name can mean two things in one file.  Take it away and
either nothing happens -- the macro simply stays defined, and most of these
undefine something that was never defined at all -- or the second #define
becomes a redefinition, which is undefined behaviour that happens to work.

So: a macro defined more than once in a file has each definition and its uses
renamed, from the table, before the #undef between them goes.  The new names
are not derivable from anything here, which is why they are data.

`#undef EXCMD` is the one that must survive: it belongs to the X-macro, and
goes when that does, in Phase 9.

Removing an #undef line cannot change the preprocessed output -- the directive
emits no tokens -- so tier 2 still applies to the phase that calls this, and it
is what proves the renames were complete.
"""

import re
import sys
from pathlib import Path

DEFINE = re.compile(r'^[ \t]*#[ \t]*define[ \t]+(\w+)')
UNDEF = re.compile(r'^[ \t]*#[ \t]*undef[ \t]+(\w+)')


def load_renames(path):
    table = {}
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        scope, old, new = line.split(':')
        if '@' in old:
            old, nth = old.split('@')
            table[(scope, old, int(nth))] = new
        else:
            table[(scope, old, None)] = new
    return table


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    table = load_renames(sys.argv[1])
    keep = {m for m in sys.argv[2].split(',') if m}
    renamed = removed = 0

    for path in sys.argv[3:]:
        p = Path(path)
        lines = p.read_text(errors='surrogateescape').split('\n')

        # Where is each macro defined?  More than once means the #undef between
        # them is load-bearing and the name has to split.
        defines = {}
        for i, line in enumerate(lines):
            m = DEFINE.match(line)
            if m:
                defines.setdefault(m.group(1), []).append(i)

        undone = {m.group(1) for m in (UNDEF.match(l) for l in lines) if m}

        for macro, at in defines.items():
            if len(at) < 2:
                continue
            # Two definitions with no #undef between them are not this pass's
            # business: they are the two arms of a conditional this phase
            # deliberately left alone, and removing #undef changes nothing
            # about them.  errors.h defines PLURAL_MSG twice exactly so, one
            # arm declaring and the other defining.
            if macro not in undone:
                continue
            # A macro whose #undef is being KEPT keeps its meaning too.  EXCMD
            # is defined twice on purpose -- ex_cmds.h is read once to declare
            # and once to define -- and it goes with the X-macro in Phase 9.
            if macro in keep:
                continue
            for nth, start in enumerate(at, 1):
                new = table.get((p.name, macro, nth))
                if new is None:
                    sys.exit('undefs: %s defines %s %d times and %s#%d is not in '
                             'the rename table -- add it rather than guessing, '
                             'or two passes will not agree'
                             % (p.name, macro, len(at), macro, nth))
                # The region runs to this macro's next #undef, or to the next
                # definition of it, whichever comes first.
                end = len(lines)
                for j in range(start + 1, len(lines)):
                    u = UNDEF.match(lines[j])
                    d = DEFINE.match(lines[j])
                    if (u and u.group(1) == macro) or (d and d.group(1) == macro):
                        end = j + 1 if u else j
                        break
                pat = re.compile(r'\b%s\b' % re.escape(macro))
                for j in range(start, end):
                    lines[j], n = pat.subn(new, lines[j])
                    renamed += n

        out = []
        for line in lines:
            u = UNDEF.match(line)
            if u and u.group(1) not in keep:
                removed += 1
                continue
            out.append(line)
        p.write_text('\n'.join(out), errors='surrogateescape')

    print('  undefs       %d removed, %d identifiers renamed, kept: %s'
          % (removed, renamed, ', '.join(sorted(keep)) or 'none'))


if __name__ == '__main__':
    main()
